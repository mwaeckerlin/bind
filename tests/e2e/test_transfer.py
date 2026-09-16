"""A secondary server pulls the zones, and only the address that TRANSFER names
is allowed to.

The `configured` service names this test runner in TRANSFER (it holds the fixed
address 10.253.53.10 in the stack), so the transfer here is the one a secondary
would do. test_hardening.py measures the other side: without TRANSFER the same
request is refused.
"""
import pytest

from conftest import CONFIGURED, transfer


def rdata(zone, name, rdtype):
    return [str(item) for item in zone.get_rdataset(name, rdtype)]


# F7 --------------------------------------------------------------------------

def test_the_secondary_receives_the_whole_zone():
    zone = transfer(CONFIGURED, "special.example")
    assert rdata(zone, "special.example.", "SOA")[0].startswith(
        "special.example. root.special.example.")
    assert rdata(zone, "special.example.", "NS") == ["special.example."]
    assert rdata(zone, "special.example.", "A") == ["10.253.53.2"]
    assert rdata(zone, "special.example.", "MX") == ["10 mail.example.com."]
    assert rdata(zone, "special.example.", "TXT") == ['"v=spf1 -all"']
    assert rdata(zone, "www.special.example.", "CNAME") == ["special.example."]
    assert rdata(zone, "lists.special.example.", "A") == ["10.253.53.3"]
    assert rdata(zone, "lists.special.example.", "MX") == ["20 special.example."]


def test_every_configured_zone_can_be_pulled():
    for name in ("transfer.example", "address.example", "records.example",
                 "default.example"):
        assert transfer(CONFIGURED, name).get_rdataset(f"{name}.", "SOA")


def test_a_zone_that_does_not_exist_is_not_transferred():
    with pytest.raises(Exception):
        transfer(CONFIGURED, "unknown.example")
