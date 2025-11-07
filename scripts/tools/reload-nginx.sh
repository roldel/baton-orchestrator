#!/bin/sh
set -eu
# Best-effort nginx reload inside your ingress container
docker exec ingress-nginx nginx -s reload 2>/dev/null || true
