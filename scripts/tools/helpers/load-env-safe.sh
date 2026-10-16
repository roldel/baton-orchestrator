#!/bin/sh
# scripts/tools/helpers/load-env-safe.sh — safely load a project's .env as
# shell variables, WITHOUT ever executing its content as shell code.
#
# `. "$ENV_FILE"` (direct sourcing, used almost everywhere in this codebase
# until now) parses the *entire file* as a shell script: a value written as
#   PAYLOAD_SIGNATURE=abc;rm -rf /some/path
# executes `rm -rf /some/path` the instant that line is sourced — regardless
# of whether PAYLOAD_SIGNATURE's value is ever subsequently used anywhere
# dangerous. Every project's .env is effectively attacker-controlled from
# that project owner's perspective, so this is full arbitrary command
# execution with the orchestrator's (often root) privileges, reachable from
# any project's own config.
#
# This file defines load_env_safe() instead: it reads a .env line-by-line
# as pure DATA (never as shell syntax) and assigns each KEY=VALUE pair via
# `eval "$key=\"\$val\""` — the same technique scripts/tools/webhook/
# handle-webhook.sh's load_task() already uses safely for task files. The
# value is substituted *inside double quotes, at eval time*, so characters
# in it (;, `, $(...), &&, a bare space, ...) are never re-parsed as shell
# syntax; they're just the string being assigned, no matter what they are.
#
# Usage (meant to be sourced — this file itself is trusted/orchestrator-
# owned, only the .env content it parses is untrusted):
#   . "$BASE_DIR/scripts/tools/helpers/load-env-safe.sh"
#   load_env_safe "$ENV_FILE"
#
# Every loaded KEY becomes an exported shell variable (matching `set -a`
# semantics), so templating callers (render-server-conf.sh) and subprocess
# callers see it the same way direct sourcing + `set -a` did.
#
# NOTE: this function does NOT protect against a project's .env redefining
# a variable this script's CALLER relies on afterward (e.g. BASE_DIR,
# TOOLS_DIR) — that's a separate concern. Callers that only need a handful
# of specific values should still call this inside an isolated subshell and
# extract just those values, exactly as before; callers that need "export
# everything" (render-server-conf.sh) should snapshot and restore their own
# trusted path variables immediately after calling this.
#
# Deliberate limitations (fails closed rather than guessing intent):
#   - A line must be exactly `KEY=value`, `KEY="value"` or `KEY='value'`.
#     KEY must match [A-Z_][A-Z0-9_]*, matching this codebase's own
#     convention (every real .env key here is UPPER_SNAKE_CASE).
#   - An UNQUOTED value ends at the first unescaped space or tab, exactly
#     like direct `.`-sourcing would terminate that shell word there — this
#     also means anything after that whitespace (including a trailing
#     ` # comment`, which this repo's own .env.sample files use) is simply
#     not part of the value, matching legacy behavior, not included as data.
#     A value starting with a quote character runs to the next matching
#     quote; anything after that closing quote must be empty or whitespace
#     only (trimmed) — again matching what direct sourcing tolerated.
#     Quoting is otherwise all-or-nothing: no backslash-escaping support,
#     and the quote character can't appear again inside the value.
#   - A line that doesn't parse cleanly, including a comment or blank line
#     with LEADING WHITESPACE before it, aborts the whole load with a
#     line-numbered error rather than silently skipping or guessing. This
#     only affects hand-edited files with unusual formatting; every .env
#     convention actually used in this repo is unaffected.
#   - A value can never contain a literal newline: this loader reads one
#     physical line at a time, so that's structural, not just checked.

load_env_safe() {
  _lesf_file="$1"

  if [ ! -f "$_lesf_file" ]; then
    echo "[load-env-safe] ERROR: file not found: $_lesf_file" >&2
    return 1
  fi

  _lesf_cr="$(printf '\r')"
  _lesf_lineno=0
  while IFS= read -r _lesf_line || [ -n "$_lesf_line" ]; do
    _lesf_lineno=$((_lesf_lineno + 1))

    # Tolerate CRLF line endings (common when a .env is hand-edited on
    # Windows or pasted from one); purely cosmetic, no safety implication.
    case "$_lesf_line" in
      *"$_lesf_cr") _lesf_line="${_lesf_line%"$_lesf_cr"}" ;;
    esac

    case "$_lesf_line" in
      ''|'#'*) continue ;;
    esac

    case "$_lesf_line" in
      *=*) ;;
      *)
        echo "[load-env-safe] ERROR: $_lesf_file:$_lesf_lineno: not a KEY=VALUE line (KEY must be [A-Z_][A-Z0-9_]*): $_lesf_line" >&2
        return 1
        ;;
    esac

    _lesf_key="${_lesf_line%%=*}"
    _lesf_val="${_lesf_line#*=}"

    # Validate the KEY in full. A glob's trailing `*` matches ANY characters
    # at that position — it is not "more of the preceding bracket class" the
    # way a regex quantifier would be — so `case "$_lesf_line" in
    # [A-Z_][A-Z0-9_]*=*)` (the previous check here) only pinned down the
    # first two characters of the line; everything between there and the
    # first `=` was unchecked. That let a line like
    # `AB$(cmd)=x` through, and $_lesf_key is interpolated unescaped into the
    # `eval` below, so an unchecked key is arbitrary shell injection the
    # instant that eval runs. Checking the extracted key against a
    # negated-class glob (`*[!A-Z0-9_]*`, mirroring the technique already
    # used correctly in compute-site-key.sh / validate-webhook-url.sh) is the
    # correct way to constrain every character, not just the first two.
    case "$_lesf_key" in
      [A-Z_]*) ;;
      *)
        echo "[load-env-safe] ERROR: $_lesf_file:$_lesf_lineno: not a KEY=VALUE line (KEY must be [A-Z_][A-Z0-9_]*): $_lesf_line" >&2
        return 1
        ;;
    esac
    case "$_lesf_key" in
      *[!A-Z0-9_]*)
        echo "[load-env-safe] ERROR: $_lesf_file:$_lesf_lineno: not a KEY=VALUE line (KEY must be [A-Z_][A-Z0-9_]*): $_lesf_line" >&2
        return 1
        ;;
    esac

    case "$_lesf_val" in
      \"*)
        # Strip the leading quote, then split at the FIRST remaining quote:
        # the content can never itself contain a quote (by construction,
        # since %% took the earliest one), so only the trailer needs
        # checking — it must be empty or whitespace-only (trimmed away),
        # matching direct sourcing's tolerance for trailing space after a
        # closing quote.
        _lesf_rest="${_lesf_val#\"}"
        case "$_lesf_rest" in
          *\"*)
            _lesf_content="${_lesf_rest%%\"*}"
            _lesf_trailer="${_lesf_rest#*\"}"
            case "$_lesf_trailer" in
              *[!\ \	]*)
                echo "[load-env-safe] ERROR: $_lesf_file:$_lesf_lineno: unexpected content after closing '\"' for $_lesf_key: $_lesf_trailer" >&2
                return 1
                ;;
            esac
            _lesf_val="$_lesf_content"
            ;;
          *)
            echo "[load-env-safe] ERROR: $_lesf_file:$_lesf_lineno: unterminated double-quoted value for $_lesf_key" >&2
            return 1
            ;;
        esac
        ;;
      \'*)
        _lesf_rest="${_lesf_val#\'}"
        case "$_lesf_rest" in
          *\'*)
            _lesf_content="${_lesf_rest%%\'*}"
            _lesf_trailer="${_lesf_rest#*\'}"
            case "$_lesf_trailer" in
              *[!\ \	]*)
                echo "[load-env-safe] ERROR: $_lesf_file:$_lesf_lineno: unexpected content after closing \"'\" for $_lesf_key: $_lesf_trailer" >&2
                return 1
                ;;
            esac
            _lesf_val="$_lesf_content"
            ;;
          *)
            echo "[load-env-safe] ERROR: $_lesf_file:$_lesf_lineno: unterminated single-quoted value for $_lesf_key" >&2
            return 1
            ;;
        esac
        ;;
      *)
        # Unquoted: ends at the first unescaped space or tab, exactly like
        # a direct-sourced shell word would — so a trailing ` # comment` or
        # trailing whitespace is simply not part of the value, same as
        # direct sourcing, rather than literal data.
        _lesf_val="${_lesf_val%%[\ \	]*}"
        ;;
    esac

    # $_lesf_val is now pure data. Expanding it *inside double quotes within
    # the eval'd string* (not inlined as raw text before eval reads it)
    # means its content is substituted as a single opaque value — nothing
    # in it is re-parsed as shell syntax, regardless of what it contains.
    eval "$_lesf_key=\"\$_lesf_val\""
    eval "export $_lesf_key"
  done < "$_lesf_file"

  unset _lesf_file _lesf_lineno _lesf_line _lesf_key _lesf_val _lesf_cr _lesf_rest _lesf_content _lesf_trailer
}
