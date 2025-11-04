#!/bin/sh
# Usage: ./domain-name-aliases-retriever.sh /path/to/server.conf
# Outputs:
#   MAIN_DOMAIN_NAME=example.com
#   DOMAIN_ALIASES="www.example.com api.example.com"

set -eu

CFG="${1:-}"
[ -n "${CFG}" ] || { echo "Usage: $(basename "$0") /path/to/server.conf" >&2; exit 1; }
[ -f "${CFG}" ] || { echo "Config not found: ${CFG}" >&2; exit 1; }

# We want the *first* server_name directive, robust to whitespace and comments.
# Handle the case where server_name might be split across lines until ';'.
# Ignore tokens that contain '$' (variables); ignore trailing ';'.

# awk program:
# - Skip commented lines.
# - When 'server_name' is found, start capturing tokens until ';' occurs (may be same or next lines).
# - Print tokens space-separated on one line; exit after first directive is processed.
NAMES=$(
  awk '
    BEGIN{cap=0}
    /^[[:space:]]*#/ { next }
    {
      if (cap==0) {
        for (i=1;i<=NF;i++) {
          if ($i ~ /^server_name$/) {
            cap=1
            # capture rest of this line after server_name
            for (j=i+1;j<=NF;j++){
              line=line" "$j
              if ($j ~ /;$/) { done=1; break }
            }
            if (done==1) { print line; exit }
            next
          }
        }
      } else {
        # continue capturing on following lines until ;
        for (i=1;i<=NF;i++){
          line=line" "$i
          if ($i ~ /;$/) { print line; exit }
        }
      }
    }
  ' "${CFG}" \
  | sed -e 's/^[[:space:]]*//' -e 's/[;[:space:]]*$//'
)

# Filter out variables (things with $) and empty fields
# Normalize spaces
NAMES_CLEAN=$(printf "%s\n" "${NAMES}" \
  | tr " \t" "\n" \
  | grep -v '\$' \
  | grep -v '^$' \
  | tr "\n" " " \
  | sed -e 's/[[:space:]]\{1,\}/ /g' -e 's/[[:space:]]*$//'
)

MAIN_DOMAIN_NAME=$(printf "%s\n" "${NAMES_CLEAN}" | awk '{print $1}')
ALIASES=$(printf "%s\n" "${NAMES_CLEAN}" | awk '{$1=""; print $0}' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

[ -n "${MAIN_DOMAIN_NAME}" ] || { echo "Could not find server_name in ${CFG}" >&2; exit 1; }

# Output as KEY=VALUE safe for: eval "$(script ...)"
printf "MAIN_DOMAIN_NAME=%s\n" "${MAIN_DOMAIN_NAME}"
# Quote the aliases as a single string, may be empty
printf 'DOMAIN_ALIASES="%s"\n' "${ALIASES}"
