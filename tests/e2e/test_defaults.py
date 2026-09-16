"""What the server does when nothing but the domains and one address is given.

The `defaults` service in tests/e2e/docker-compose.yml sets no other build
argument, so every value measured here is a default of
generate-configuration.sh and README.md names the same ones.
"""
from conftest import (DEFAULTS, DEFAULT_EXPIRE, DEFAULT_NEGATIVE_CACHE_TTL,
                      DEFAULT_REFRESH, DEFAULT_RETRY, DEFAULT_TTL,
                      records, ttl)


ADDRESS = "10.1.0.1"


# F6 --------------------------------------------------------------------------

def test_default_time_to_live():
    assert ttl(DEFAULTS, "bare.example", "A") == DEFAULT_TTL


def test_default_times_of_the_zone():
    answer = records(DEFAULTS, "bare.example", "SOA")[0].split()
    assert answer[3:] == [DEFAULT_REFRESH, DEFAULT_RETRY, DEFAULT_EXPIRE,
                          DEFAULT_NEGATIVE_CACHE_TTL]


def test_the_serial_is_the_build_time():
    serial = records(DEFAULTS, "bare.example", "SOA")[0].split()[2]
    assert serial.isdigit() and len(serial) >= 9


# F5 --------------------------------------------------------------------------

def test_without_a_mail_server_the_domain_is_its_own():
    assert records(DEFAULTS, "bare.example", "MX") == ["10 bare.example."]


# F2 --------------------------------------------------------------------------

def test_without_a_subdomain_list_every_name_answers():
    for name in ("www.bare.example", "anything.bare.example"):
        assert records(DEFAULTS, name, "CNAME") == ["bare.example."]


# F1 --------------------------------------------------------------------------

def test_a_domain_from_the_default_list():
    assert records(DEFAULTS, "bare.example", "A") == [ADDRESS]


def test_a_domain_that_names_no_address():
    assert records(DEFAULTS, "listed.example", "A") == [ADDRESS]


def test_a_domain_that_names_its_address():
    assert records(DEFAULTS, "address.example", "A") == ["10.1.0.2"]
