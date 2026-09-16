#!/usr/bin/env python3
"""Print the configuration of a service in docker-compose.yaml as shell assignments.

The configuration of this project lives in the build arguments of
docker-compose.yaml. The tests read it from there, so the domain list exists
once and a test can never measure a state that nobody built.

Usage: config.py [compose-file] [service]
"""

import json
import pathlib
import shlex
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

VARIABLES = (
    "TTL",
    "SERIAL",
    "REFRESH",
    "RETRY",
    "EXPIRE",
    "NEGATIVE_CACHE_TTL",
    "SEVERITY",
    "TRANSFER",
    "MAILSERVER",
    "DEFAULT_IP",
    "DEFAULT_SUBDOMAINS",
    "DEFAULT_DOMAINS",
    "DOMAINS",
)


def main():
    compose = sys.argv[1] if len(sys.argv) > 1 else "docker-compose.yaml"
    service = sys.argv[2] if len(sys.argv) > 2 else "bind"
    result = subprocess.run(
        ["docker", "compose", "--file", compose, "config", "--format", "json"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    if result.returncode:
        sys.exit(result.stderr.strip() or "docker compose config failed")
    services = json.loads(result.stdout)["services"]
    if service not in services:
        sys.exit(f"no service {service} in {compose}")
    arguments = services[service].get("build", {}).get("args", {})
    for name in VARIABLES:
        value = arguments.get(name)
        print(f"{name}={shlex.quote(value if value is not None else '')}")


if __name__ == "__main__":
    main()
