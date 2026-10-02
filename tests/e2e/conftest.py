"""Shared fixtures: the addresses of the bind services, the configuration they
were built from, and DNS helpers.

The configuration of the `production` service is not written down here: it is
passed in through the environment by tests/run-e2e.sh, which reads it out of
docker-compose.yaml. So the domain list exists once, and a test can never
measure a state that nobody built.

The configurations of the other services stand in tests/e2e/docker-compose.yml
and the expected value stands in the test that measures it; when the two drift
apart the test goes red instead of passing silently.
"""
import os
import socket
import time

import dns.exception
import dns.message
import dns.query
import dns.rcode
import dns.rdataclass
import dns.zone
import pytest


# ----------------------------------------------------------------- Config ---

PRODUCTION = os.environ.get("PRODUCTION_SERVER", "production")
DEFAULTS = os.environ.get("DEFAULTS_SERVER", "defaults")
CONFIGURED = os.environ.get("CONFIGURED_SERVER", "configured")
MOUNTED = os.environ.get("MOUNTED_SERVER", "mounted")
RECURSIVE = os.environ.get("RECURSIVE_SERVER", "recursive")
PORT = int(os.environ.get("BIND_PORT", "9953"))

# the defaults of generate-configuration.sh, as documented in README.md; they
# are written out here on purpose, a test that asks the code under test for its
# expectation proves nothing
DEFAULT_TTL = "3600"
DEFAULT_REFRESH = "3600"
DEFAULT_RETRY = "1800"
DEFAULT_EXPIRE = "604800"
DEFAULT_NEGATIVE_CACHE_TTL = "1800"
DEFAULT_SUBDOMAINS = "*"


# ------------------------------------------------------------- The domains ---

class Domain:
    """One line of DOMAINS or DEFAULT_DOMAINS, parsed the way
    generate-configuration.sh parses it."""

    def __init__(self, line, default_ip, default_subdomains):
        self.name, _, rest = line.partition("=")
        address, _, rest = rest.partition(";")
        self.address = address or default_ip
        subdomains, _, rest = rest.partition(";")
        self.subdomains = (subdomains or default_subdomains).split()
        self.records = [r for r in rest.split(";") if r.strip()]

    def __repr__(self):
        return self.name


def configuration(prefix=""):
    """The build arguments of a service, read from the environment."""
    return {
        name: os.environ.get(prefix + name, "")
        for name in ("TTL", "SERIAL", "REFRESH", "RETRY", "EXPIRE",
                     "NEGATIVE_CACHE_TTL", "SEVERITY", "TRANSFER", "RECURSION",
                     "RATE_LIMIT", "MAILSERVER", "DEFAULT_IP",
                     "DEFAULT_SUBDOMAINS", "DEFAULT_DOMAINS", "DOMAINS")
    }


def domains(config):
    lines = config["DOMAINS"].splitlines() + config["DEFAULT_DOMAINS"].split()
    return [
        Domain(line.strip(), config["DEFAULT_IP"],
               config["DEFAULT_SUBDOMAINS"] or DEFAULT_SUBDOMAINS)
        for line in lines if line.strip()
    ]


PRODUCTION_CONFIG = configuration()
PRODUCTION_DOMAINS = domains(PRODUCTION_CONFIG)


# ------------------------------------------------------------- DNS helpers ---

def address(server):
    return socket.gethostbyname(server)


def response(server, name, rdtype="A", rdclass=dns.rdataclass.IN, tcp=False,
             timeout=5):
    message = dns.message.make_query(name, rdtype, rdclass=rdclass)
    send = dns.query.tcp if tcp else dns.query.udp
    return send(message, address(server), port=PORT, timeout=timeout)


def records(server, name, rdtype="A", **kwargs):
    """The answer section as a list of strings, in the order bind sent it."""
    answer = response(server, name, rdtype, **kwargs)
    return [str(item) for section in answer.answer for item in section]


def ttl(server, name, rdtype="A"):
    answer = response(server, name, rdtype)
    return str(answer.answer[0].ttl) if answer.answer else ""


def transfer(server, zone):
    """The whole zone, pulled with AXFR, with the names as they stand on the
    wire; raises when the server refuses."""
    return dns.zone.from_xfr(
        dns.query.xfr(address(server), zone, port=PORT, timeout=10,
                      relativize=False),
        relativize=False)


def wait_for_dns(server, name, timeout=60):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        try:
            if response(server, name, "SOA", timeout=2).answer:
                return
        except (dns.exception.DNSException, OSError) as exc:
            last = exc
        time.sleep(1)
    raise TimeoutError(f"{server} did not answer for {name} in {timeout}s: {last}")


# --------------------------------------------------------------- Fixtures ---

ZONES = {
    "production": (PRODUCTION, lambda: PRODUCTION_DOMAINS[0].name),
    "defaults": (DEFAULTS, lambda: "bare.example"),
    "configured": (CONFIGURED, lambda: "transfer.example"),
    "mounted": (MOUNTED, lambda: "mounted.example"),
    "recursive": (RECURSIVE, lambda: "recursive.example"),
}


@pytest.fixture(scope="session", autouse=True)
def wait_for_services():
    # test.sh asks one server of its own and starts none of the others, so it
    # names the ones it needs
    wanted = os.environ.get("WAIT_FOR", " ".join(ZONES)).split()
    for key in wanted:
        server, zone = ZONES[key]
        wait_for_dns(server, zone())
