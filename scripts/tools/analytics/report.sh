#!/bin/sh
# Baton Orchestrator - simple traffic report from nginx docker logs
#
# Default: show last 24h of traffic for all hosts routed through ingress-nginx.
#
# Options:
#   --since <window>   Time window passed to `docker logs --since` (default: 24h)
#                      Examples: 12h, 48h, 1h, 30m, 168h (≈ 7 days)
#   --host <hostname>  Filter to a specific Host (e.g. example.com)
#   -h, --help         Show usage
#
# Examples:
#   scripts/tools/analytics/report.sh
#   scripts/tools/analytics/report.sh --since 168h
#   scripts/tools/analytics/report.sh --host airlinememo.com --since 48h

set -eu

CONTAINER_NAME="ingress-nginx"
SINCE="24h"
HOST_FILTER=""

usage() {
  cat <<EOF
Usage: $0 [--since <window>] [--host <hostname>]

Generate a simple traffic report from nginx logs in the Docker container
"${CONTAINER_NAME}".

Options:
  --since <window>    Time window passed to 'docker logs --since'. Default: 24h
                      Examples: 12h, 48h, 1h, 30m, 168h (≈ 7 days)
  --host <hostname>   Only include requests for a specific Host
  -h, --help          Show this help

Examples:
  $0
  $0 --since 168h
  $0 --host airlinememo.com --since 48h
EOF
}

# --- Parse arguments ---
while [ "$#" -gt 0 ]; do
  case "$1" in
    --since)
      if [ "$#" -lt 2 ]; then
        echo "ERROR: Missing value for --since" >&2
        exit 1
      fi
      SINCE="$2"
      shift 2
      ;;
    --host)
      if [ "$#" -lt 2 ]; then
        echo "ERROR: Missing value for --host" >&2
        exit 1
      fi
      HOST_FILTER="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

# --- Basic checks ---
if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker command not found." >&2
  exit 1
fi

# Not fatal if container is stopped, but warn
if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
  echo "[report] WARNING: Container '$CONTAINER_NAME' not running; trying logs anyway..." >&2
fi

echo "[report] Container : $CONTAINER_NAME"
echo "[report] Since     : $SINCE"
[ -n "$HOST_FILTER" ] && echo "[report] Host      : $HOST_FILTER"
echo

# --- Generate report ---
docker logs --since "$SINCE" "$CONTAINER_NAME" 2>/dev/null | \
awk -v host_filter="$HOST_FILTER" '
  # We expect nginx access log format like:
  #
  #   $host $remote_addr - - [time] "METHOD /path HTTP/x.x" status bytes "ref" "ua" "xff"
  #
  # The container also prints other lines (entrypoint, ipv6 helper, etc.).
  # We:
  #   - Ignore obvious non-request lines by host pattern
  #   - Extract the quoted request "METHOD /path HTTP/x.x"
  #   - Parse out PATH from that request
  #   - Aggregate:
  #       host_hits[host]++
  #       host_url_hits[host SUBSEP path]++

  {
    if (NF == 0) {
      next
    }

    host = $1

    # Filter out internal / noisy hosts we do not want in the report
    if (host == "0.0.0.0") {
      # e.g. health checks: 0.0.0.0 127.0.0.1 - - [..] "GET /health" ...
      next
    }
    if (host ~ /docker-entrypoint\.sh/) {
      # e.g. /docker-entrypoint.sh: Configuration complete; ready for start up
      next
    }
    if (host ~ /listen-on-ipv6/) {
      # e.g. 10-listen-on-ipv6-by-default.sh: ...
      next
    }

    # Extract the quoted request part: "METHOD /path HTTP/x.x"
    if (!match($0, /"[^"]+"/)) {
      # No quoted request → not an access log line
      next
    }

    req = substr($0, RSTART + 1, RLENGTH - 2)  # drop surrounding quotes

    # Split request into parts: METHOD, PATH, PROTOCOL
    n = split(req, reqparts, " ")
    if (n < 2) {
      # We expect at least METHOD and PATH
      next
    }

    path = reqparts[2]

    # Optional host filter from CLI
    if (host_filter != "" && host != host_filter) {
      next
    }

    host_hits[host]++
    key = host SUBSEP path
    host_url_hits[key]++
  }

  END {
    if (length(host_hits) == 0) {
      print "No matching log entries in the selected window."
      exit 0
    }

    # Collect hosts into an array
    n_hosts = 0
    for (h in host_hits) {
      n_hosts++
      hosts[n_hosts] = h
    }

    # --- Sort hosts by total visits (descending) ---
    # Simple bubble sort, POSIX awk compatible
    for (i = 1; i <= n_hosts; i++) {
      for (j = i + 1; j <= n_hosts; j++) {
        if (host_hits[hosts[j]] > host_hits[hosts[i]]) {
          tmp = hosts[i]
          hosts[i] = hosts[j]
          hosts[j] = tmp
        }
      }
    }

    # For each host, collect and sort its URLs, then print stats
    for (i = 1; i <= n_hosts; i++) {
      h = hosts[i]
      printf "Host: %s\n", h
      printf "  Total visits: %d\n", host_hits[h]
      printf "  Visits per URL:\n"

      n_urls = 0
      delete urls_seen
      delete urls

      # Collect unique URLs for this host
      for (k in host_url_hits) {
        split(k, parts, SUBSEP)
        hh   = parts[1]
        path = parts[2]
        if (hh == h && !(path in urls_seen)) {
          urls_seen[path] = 1
          n_urls++
          urls[n_urls] = path
        }
      }

      # --- Sort URLs by hit count (descending) for this host ---
      for (u = 1; u <= n_urls; u++) {
        for (v = u + 1; v <= n_urls; v++) {
          keyu = h SUBSEP urls[u]
          keyv = h SUBSEP urls[v]
          if (host_url_hits[keyv] > host_url_hits[keyu]) {
            tmp = urls[u]
            urls[u] = urls[v]
            urls[v] = tmp
          }
        }
      }

      # Print URL hit counts (most visited first)
      for (u = 1; u <= n_urls; u++) {
        path = urls[u]
        key  = h SUBSEP path
        printf "    %s : %d\n", path, host_url_hits[key]
      }

      printf "\n"
    }
  }
'
