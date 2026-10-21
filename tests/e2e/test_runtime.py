"""A configuration given in the environment when the container starts.

The `runtime` service in tests/e2e/docker-compose.yml is built with a time to
live, an address, its default subdomains and the domain built.example, and it
is started with DOMAINS, MAILSERVER, NAMESERVER and HOSTMASTER in the
environment. A variable given at start replaces the value of the build, every
other value of the build stays the default.
"""
from conftest import RUNTIME, records, ttl


BUILT_TTL = "900"
BUILT_ADDRESS = "10.5.0.1"


# F18 -------------------------------------------------------------------------

def test_a_domain_given_at_start_answers():
    assert records(RUNTIME, "runtime.example", "A") == [BUILT_ADDRESS]


def test_a_domain_given_at_start_with_its_own_address():
    assert records(RUNTIME, "own.example", "A") == ["10.5.0.2"]


def test_its_subdomain_and_free_form_record():
    assert records(RUNTIME, "lists.own.example", "A") == ["10.5.0.3"]
    assert '"v=spf1 -all"' in records(RUNTIME, "own.example", "TXT")


def test_the_subdomains_of_the_build_stay_the_default():
    assert records(RUNTIME, "www.runtime.example", "CNAME") == ["runtime.example."]
    assert records(RUNTIME, "anything.runtime.example", "CNAME") == []


def test_the_time_to_live_of_the_build_stays_the_default():
    assert ttl(RUNTIME, "runtime.example", "A") == BUILT_TTL


def test_the_domains_of_the_build_are_replaced():
    assert records(RUNTIME, "built.example", "A") == []


def test_the_serial_is_the_start_time():
    serial = records(RUNTIME, "runtime.example", "SOA")[0].split()[2]
    assert serial.isdigit() and len(serial) >= 9


# F5 --------------------------------------------------------------------------

def test_the_mail_server_given_at_start():
    for domain in ("runtime.example", "own.example"):
        assert records(RUNTIME, domain, "MX") == ["10 mail.example.com."]


# F19 -------------------------------------------------------------------------

def test_the_name_server_given_at_start():
    for domain in ("runtime.example", "own.example"):
        assert records(RUNTIME, domain, "NS") == ["ns1.example.com."]


# F20 -------------------------------------------------------------------------

def test_the_hostmaster_given_at_start():
    for domain in ("runtime.example", "own.example"):
        server, mailbox = records(RUNTIME, domain, "SOA")[0].split()[:2]
        assert (server, mailbox) == (f"{domain}.", "hostmaster.example.com.")
