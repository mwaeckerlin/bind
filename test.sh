#!/usr/bin/env bash
# Ask a running bind server for every record the configuration of
# docker-compose.yaml promises. This is the check of a deployment: the same
# tests that tests/run-e2e.sh runs against the built container run against the
# server that is actually serving.
#
#   ./test.sh                  the whole e2e suite against the built image
#   ./test.sh ns1.example.com  a deployed server, port 53
#   ./test.sh localhost 9953   a server on another port
set -euo pipefail

COMPOSE="tests/e2e/docker-compose.yml"
cd "$(dirname "$0")"

if [[ $# -eq 0 ]]; then
    exec bash tests/run-e2e.sh
fi

SERVER="$1"
PORT="${2:-53}"
shift $(( $# > 1 ? 2 : 1 ))

eval "$(python3 tests/config.py)"
export TTL SERIAL REFRESH RETRY EXPIRE NEGATIVE_CACHE_TTL SEVERITY TRANSFER \
    MAILSERVER DEFAULT_IP DEFAULT_SUBDOMAINS DEFAULT_DOMAINS DOMAINS

echo "==> Building the test runner..."
docker compose -f "$COMPOSE" build --quiet test-runner

echo "==> Asking ${SERVER} on port ${PORT}..."
docker compose -f "$COMPOSE" run --rm --no-deps \
    -e PRODUCTION_SERVER="$SERVER" -e BIND_PORT="$PORT" -e WAIT_FOR=production \
    test-runner pytest -q --tb=short \
    test_records.py test_transport.py test_hardening.py "$@"
