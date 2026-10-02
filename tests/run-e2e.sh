#!/usr/bin/env bash
# Run the full bind e2e test suite covering every supported usage (the
# configuration of docker-compose.yaml, the defaults, every build argument with
# a value of its own, and a configuration mounted at run time).
#
# The configuration of the production service is read out of
# docker-compose.yaml and handed to the stack through the environment, so the
# domain list exists once: what is built is what is measured.
# Usage: bash tests/run-e2e.sh [pytest-args...]
set -euo pipefail

COMPOSE="tests/e2e/docker-compose.yml"
cd "$(dirname "$0")/.."

eval "$(python3 tests/config.py)"
export TTL SERIAL REFRESH RETRY EXPIRE NEGATIVE_CACHE_TTL SEVERITY TRANSFER \
    MAILSERVER DEFAULT_IP DEFAULT_SUBDOMAINS DEFAULT_DOMAINS DOMAINS

cleanup() {
    docker compose -f "$COMPOSE" down -v --remove-orphans 2>/dev/null || true
}
trap cleanup EXIT

echo "==> Building test stack..."
docker compose -f "$COMPOSE" build --quiet

echo "==> Starting services..."
docker compose -f "$COMPOSE" up -d --remove-orphans production defaults configured mounted recursive

echo "==> Running tests..."
EXIT=0
docker compose -f "$COMPOSE" run --rm test-runner "$@" || EXIT=$?

echo "==> Checking the log level..."
# the production service runs at the default level and must not log a line per
# query, the configured service runs at level info and must
if docker compose -f "$COMPOSE" logs production 2>&1 | grep -q 'queries: info: client'; then
    echo "FAIL: the default log level logs every single query"
    EXIT=1
fi
if ! docker compose -f "$COMPOSE" logs configured 2>&1 | grep -q 'queries: info: client'; then
    echo "FAIL: SEVERITY=info does not reach the server"
    EXIT=1
fi

if [[ $EXIT -ne 0 ]]; then
    echo "==> Collecting logs on failure..."
    docker compose -f "$COMPOSE" logs 2>&1 | tail -120
fi

exit $EXIT
