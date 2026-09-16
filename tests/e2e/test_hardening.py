"""The server answers for its own zones and gives nothing else away.

Recursion, zone transfer, version disclosure and the remote control channel are
the four ways an authoritative server is abused; the generated configuration
switches all four off and these tests measure the running server.
"""
import dns.rcode
import dns.rdataclass
import pytest

from conftest import PRODUCTION, PRODUCTION_DOMAINS, records, response, transfer


# F8 --------------------------------------------------------------------------

# a name no configuration of this project serves — .invalid is reserved for
# exactly that (RFC 2606), so no zone of any test server can ever cover it
FOREIGN = "not-served.invalid"


def test_recursion_is_refused():
    answer = response(PRODUCTION, FOREIGN, "A")
    assert answer.rcode() == dns.rcode.REFUSED


def test_the_version_is_not_disclosed():
    assert records(PRODUCTION, "version.bind", "TXT",
                   rdclass=dns.rdataclass.CH) == []


def test_a_foreign_zone_is_not_answered():
    answer = response(PRODUCTION, FOREIGN, "SOA")
    assert answer.answer == []


# F7 --------------------------------------------------------------------------

def test_the_zone_transfer_is_refused():
    # without TRANSFER the whole list of domains and hosts must stay unreachable
    with pytest.raises(Exception):
        transfer(PRODUCTION, PRODUCTION_DOMAINS[0].name)
