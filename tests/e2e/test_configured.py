"""Every variable of the configuration, each with a value of its own.

The `configured` service in tests/e2e/docker-compose.yml sets every build
argument the image knows; the values expected here are exactly the ones that
stand there, so a change on one side turns this file red.
"""
from conftest import CONFIGURED, records, ttl


SERIAL = "2026091601"
TTL = "900"
REFRESH, RETRY, EXPIRE, NEGATIVE_CACHE_TTL = "1200", "600", "86400", "300"
MAILSERVER = "mail.example.com"
DEFAULT_IP = "10.253.53.1"


# F6 --------------------------------------------------------------------------

def test_serial_number():
    assert records(CONFIGURED, "transfer.example", "SOA")[0].split()[2] == SERIAL


def test_times_of_the_zone():
    answer = records(CONFIGURED, "transfer.example", "SOA")[0].split()
    assert answer[3:] == [REFRESH, RETRY, EXPIRE, NEGATIVE_CACHE_TTL]


def test_time_to_live():
    assert ttl(CONFIGURED, "transfer.example", "A") == TTL


# F5 --------------------------------------------------------------------------

def test_mail_server_of_every_domain():
    # MAILSERVER replaces the default globally: without it every zone is its
    # own mail server, with it every zone names this one host — the domain
    # with its own address and the one with its own subdomains included
    for domain in ("transfer.example", "special.example", "address.example",
                   "records.example", "empty.example", "default.example"):
        assert records(CONFIGURED, domain, "MX") == [f"10 {MAILSERVER}."]


# F1 --------------------------------------------------------------------------

def test_default_address():
    assert records(CONFIGURED, "transfer.example", "A") == [DEFAULT_IP]


def test_domain_with_its_own_address():
    assert records(CONFIGURED, "special.example", "A") == ["10.253.53.2"]


def test_domain_that_names_nothing_but_its_address():
    assert records(CONFIGURED, "address.example", "A") == ["10.253.53.4"]
    assert records(CONFIGURED, "www.address.example", "CNAME") == ["address.example."]


def test_domain_from_the_default_list():
    assert records(CONFIGURED, "default.example", "A") == [DEFAULT_IP]


def test_domain_whose_entry_ends_after_the_equals_sign():
    # `name=` names neither an address nor subdomains: both fall back
    assert records(CONFIGURED, "empty.example", "A") == [DEFAULT_IP]
    assert records(CONFIGURED, "www.empty.example", "CNAME") == ["empty.example."]
    assert records(CONFIGURED, "mail.empty.example", "CNAME") == ["empty.example."]


# F2 --------------------------------------------------------------------------

def test_default_subdomains():
    for name in ("www.transfer.example", "mail.transfer.example"):
        assert records(CONFIGURED, name, "CNAME") == ["transfer.example."]


def test_own_subdomain_list_replaces_the_default_one():
    assert records(CONFIGURED, "www.special.example", "CNAME") == ["special.example."]
    assert records(CONFIGURED, "mail.special.example", "CNAME") == []


def test_a_subdomain_name_may_carry_a_dot():
    assert records(CONFIGURED, "old.www.special.example", "CNAME") == ["special.example."]
    assert records(CONFIGURED, "old.www.special.example", "A")[-1] == "10.253.53.2"


# F3 --------------------------------------------------------------------------

def test_subdomain_on_its_own_address():
    assert records(CONFIGURED, "lists.special.example", "A") == ["10.253.53.3"]
    assert records(CONFIGURED, "lists.special.example", "CNAME") == []


def test_subdomain_with_an_address_of_the_sixth_version():
    assert records(CONFIGURED, "host.records.example", "AAAA") == ["2001:db8::1"]


def test_subdomain_that_points_at_another_domain():
    assert records(CONFIGURED, "alias.records.example", "CNAME") == ["special.example."]


# F4 --------------------------------------------------------------------------

def test_free_form_text_record():
    assert '"v=spf1 -all"' in records(CONFIGURED, "special.example", "TXT")


def test_free_form_mail_record():
    assert "20 special.example." in records(CONFIGURED, "lists.special.example", "MX")
