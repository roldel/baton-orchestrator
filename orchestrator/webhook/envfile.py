"""Project .env reader that follows scripts/tools/helpers/load-env-safe.sh.

No interpolation, no ``export`` prefix, no backslash escapes. A bad line
fails that file only. Callers decide what to do with EnvParseError.
"""

import logging
import os
import re

logger = logging.getLogger(__name__)

_KEY_RE = re.compile(r"^[A-Z_][A-Z0-9_]*$")

# Same reserved names as load_env_safe. A project file that sets one of
# these is rejected so the container and the host worker agree.
_RESERVED = {
    "PATH",
    "IFS",
    "CDPATH",
    "ENV",
    "BASH_ENV",
    "SHELLOPTS",
    "BASHOPTS",
    "LD_PRELOAD",
    "LD_LIBRARY_PATH",
    "LD_AUDIT",
    "LD_DEBUG",
    "LD_PROFILE",
    "GLIBC_TUNABLES",
    "PYTHONPATH",
    "PYTHONHOME",
    "PERL5OPT",
    "GIT_DIR",
    "GIT_WORK_TREE",
    "GIT_SSH_COMMAND",
    "GIT_CONFIG_COUNT",
}


class EnvParseError(Exception):
    pass


class HostConflict(Exception):
    def __init__(self, host, first, second):
        self.host = host
        self.first = first
        self.second = second
        super().__init__(
            "host %r matches both %r and %r" % (host, first, second)
        )


def _reserved(key):
    if key in _RESERVED:
        return True
    return key.startswith("GIT_CONFIG_KEY_") or key.startswith("GIT_CONFIG_VALUE_")


def _parse_value(val, path, lineno, key):
    if val.startswith('"'):
        quote = '"'
    elif val.startswith("'"):
        quote = "'"
    else:
        for index, ch in enumerate(val):
            if ch in " \t":
                return val[:index]
        return val

    rest = val[1:]
    end = rest.find(quote)
    if end < 0:
        raise EnvParseError(
            "%s:%d: unterminated quoted value for %s" % (path, lineno, key)
        )
    trailer = rest[end + 1 :]
    if trailer.strip(" \t") != "":
        raise EnvParseError(
            "%s:%d: unexpected content after closing quote for %s"
            % (path, lineno, key)
        )
    return rest[:end]


def parse_env_file(path):
    """Return a dict of KEY=value pairs. Raises EnvParseError or OSError."""
    env = {}
    with open(path, "r", encoding="utf-8", newline="") as handle:
        text = handle.read()
    for lineno, line in enumerate(text.splitlines(), 1):
        if line.endswith("\r"):
            line = line[:-1]
        if line == "" or line.startswith("#"):
            continue
        if "=" not in line:
            raise EnvParseError(
                "%s:%d: not a KEY=VALUE line: %s" % (path, lineno, line)
            )
        key, raw = line.split("=", 1)
        if not _KEY_RE.match(key) or _reserved(key):
            raise EnvParseError(
                "%s:%d: not a KEY=VALUE line (KEY must be [A-Z_][A-Z0-9_]*): %s"
                % (path, lineno, line)
            )
        env[key] = _parse_value(raw, path, lineno, key)
    return env


def _domains(env):
    domain_name = (env.get("DOMAIN_NAME") or "").lower()
    if not domain_name:
        return []
    aliases = env.get("DOMAIN_ALIASES") or ""
    alias_list = [
        part.strip().lower()
        for part in aliases.replace(",", " ").split()
        if part.strip()
    ]
    return [domain_name] + alias_list


def find_project_by_host(host, projects_dir):
    """Return (project_name, env) or (None, None).

    An unreadable or invalid .env is skipped. Two projects that claim the
    same host raise HostConflict; neither one is chosen.
    """
    host = (host or "").split(":", 1)[0].lower()
    match_name = None
    match_env = None

    for project_name in sorted(os.listdir(projects_dir)):
        project_path = os.path.join(projects_dir, project_name)
        try:
            if not os.path.isdir(project_path):
                continue
            env_path = os.path.join(project_path, ".env")
            if not os.path.isfile(env_path):
                continue
            env = parse_env_file(env_path)
        except OSError as exc:
            logger.warning("skipping %s: %s", project_path, exc)
            continue
        except EnvParseError as exc:
            logger.warning("skipping %s: %s", project_path, exc)
            continue

        if host not in _domains(env):
            continue
        if match_name is not None:
            logger.warning(
                "Host %r matches multiple projects (%r and %r); refusing both",
                host,
                match_name,
                project_name,
            )
            raise HostConflict(host, match_name, project_name)
        match_name, match_env = project_name, env

    if match_name is None:
        return None, None
    return match_name, match_env
