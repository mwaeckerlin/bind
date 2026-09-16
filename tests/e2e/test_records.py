"""Every record of every configured domain, against the configuration the
server was built from.

The domains come from docker-compose.yaml through the environment (conftest),
so this file names no domain of its own: what is built is what is measured.
"""
import pytest

from conftest import (DEFAULT_EXPIRE, DEFAULT_NEGATIVE_CACHE_TTL,
                      DEFAULT_REFRESH, DEFAULT_RETRY, DEFAULT_TTL,
                      PRODUCTION, PRODUCTION_CONFIG, PRODUCTION_DOMAINS,
                      records, ttl)


CONFIG = PRODUCTION_CONFIG
EXPECTED_TTL = CONFIG["TTL"] or DEFAULT_TTL


def times():
    return (CONFIG["REFRESH"] or DEFAULT_REFRESH,
            CONFIG["RETRY"] or DEFAULT_RETRY,
            CONFIG["EXPIRE"] or DEFAULT_EXPIRE,
            CONFIG["NEGATIVE_CACHE_TTL"] or DEFAULT_NEGATIVE_CACHE_TTL)


def fields(record):
    """A free form record `name [ttl] IN TYPE rdata` split into its parts."""
    parts = record.replace("\\t", " ").split()
    position = parts.index("IN")
    return parts[0], parts[position + 1], " ".join(parts[position + 2:])


# F1 --------------------------------------------------------------------------

@pytest.mark.parametrize("domain", PRODUCTION_DOMAINS, ids=str)
def test_domain_address(domain):
    assert records(PRODUCTION, domain.name, "A") == [domain.address]


@pytest.mark.parametrize("domain", PRODUCTION_DOMAINS, ids=str)
def test_domain_name_server(domain):
    assert records(PRODUCTION, domain.name, "NS") == [f"{domain.name}."]


@pytest.mark.parametrize("domain", PRODUCTION_DOMAINS, ids=str)
def test_domain_start_of_authority(domain):
    answer = records(PRODUCTION, domain.name, "SOA")
    assert len(answer) == 1
    server, mailbox, serial, refresh, retry, expire, negative = answer[0].split()
    assert (server, mailbox) == (f"{domain.name}.", f"root.{domain.name}.")
    assert (refresh, retry, expire, negative) == times()
    assert CONFIG["SERIAL"] in ("", serial)


# F6 --------------------------------------------------------------------------

@pytest.mark.parametrize("domain", PRODUCTION_DOMAINS, ids=str)
def test_domain_time_to_live(domain):
    assert ttl(PRODUCTION, domain.name, "A") == EXPECTED_TTL


# F5 --------------------------------------------------------------------------

@pytest.mark.parametrize("domain", PRODUCTION_DOMAINS, ids=str)
def test_domain_mail_server(domain):
    mailserver = CONFIG["MAILSERVER"] or domain.name
    assert records(PRODUCTION, domain.name, "MX") == [f"10 {mailserver}."]


# F2, F3 ----------------------------------------------------------------------

@pytest.mark.parametrize("domain", PRODUCTION_DOMAINS, ids=str)
def test_subdomains(domain):
    for subdomain in domain.subdomains:
        name, _, value = subdomain.partition("=")
        full = f"{name}.{domain.name}"
        if not value:
            # an ordinary subdomain is a CNAME onto its domain and resolves to
            # the address of that domain
            assert records(PRODUCTION, full, "CNAME") == [f"{domain.name}."]
            assert records(PRODUCTION, full, "A")[-1] == domain.address
        else:
            # name=TYPE:value carries that record and no CNAME
            rdtype, _, rdata = value.partition(":")
            assert records(PRODUCTION, full, rdtype) == [rdata]
            if rdtype != "CNAME":
                assert records(PRODUCTION, full, "CNAME") == []


# F4 --------------------------------------------------------------------------

@pytest.mark.parametrize(
    "domain", [d for d in PRODUCTION_DOMAINS if d.records], ids=str)
def test_free_form_records(domain):
    for record in domain.records:
        name, rdtype, rdata = fields(record)
        full = domain.name if name == "@" else f"{name}.{domain.name}"
        assert rdata in records(PRODUCTION, full, rdtype)
