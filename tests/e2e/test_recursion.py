"""Looking foreign names up, and the limit on identical answers.

Both are switched off unless the configuration names them. The `recursive`
service in tests/e2e/docker-compose.yml switches both on — `RECURSION: any`
makes it an open resolver, `RATE_LIMIT: 5` limits it — and `production` is the
other side of both.
"""
import dns.exception
import dns.flags
import dns.rcode

from conftest import PRODUCTION, RECURSIVE, records, response


# a name no server of this stack serves, so only recursion could answer it
FOREIGN = "not-served.invalid"
RATE_LIMIT = 5
BURST = 60


def answered(server, name, count):
    """How many of `count` identical queries come back with a full answer.

    A response the server holds back is either dropped — the query runs into
    its timeout — or sent truncated, which is what bind's `slip` does; neither
    counts as an answer.
    """
    full = 0
    for _ in range(count):
        try:
            reply = response(server, name, "A", timeout=2)
        except dns.exception.DNSException:
            continue
        if not reply.flags & dns.flags.TC and reply.answer:
            full += 1
    return full


# F15 -------------------------------------------------------------------------

def test_without_the_variable_a_foreign_name_is_refused():
    assert response(PRODUCTION, FOREIGN, "A").rcode() == dns.rcode.REFUSED


def test_with_the_variable_a_foreign_name_is_accepted():
    # the test network has no way to the root servers, so the lookup fails —
    # but it is attempted, and that is the difference to REFUSED
    assert response(RECURSIVE, FOREIGN, "A").rcode() != dns.rcode.REFUSED


def test_the_recursive_server_still_answers_its_own_zone():
    assert records(RECURSIVE, "recursive.example", "A") == ["10.4.0.1"]
    assert records(RECURSIVE, "www.recursive.example", "CNAME") == ["recursive.example."]


# F16 -------------------------------------------------------------------------

def test_without_the_variable_every_answer_is_sent():
    assert answered(PRODUCTION, "example.com", BURST) == BURST


def test_with_the_variable_identical_answers_are_limited():
    full = answered(RECURSIVE, "recursive.example", BURST)
    assert full < BURST, "the rate limit let every single answer through"
    assert full >= RATE_LIMIT, "the rate limit answered nobody at all"
