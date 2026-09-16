"""The service answers over UDP and over TCP.

A client falls back to TCP whenever an answer does not fit into one datagram,
and a zone transfer runs over TCP only; a server that listens on UDP alone
looks healthy until the first large answer.
"""
from conftest import PRODUCTION, PRODUCTION_DOMAINS, records


DOMAIN = PRODUCTION_DOMAINS[0]


# F12 -------------------------------------------------------------------------

def test_the_same_answer_over_both_transports():
    over_udp = records(PRODUCTION, DOMAIN.name, "A")
    over_tcp = records(PRODUCTION, DOMAIN.name, "A", tcp=True)
    assert over_udp == [DOMAIN.address]
    assert over_tcp == over_udp
