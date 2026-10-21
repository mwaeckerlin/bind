#!/bin/sh -e

# The configuration of the build: the values come from domains.sh and from the
# build arguments, and the init of the image writes it, the same program that
# writes it at start when a variable is given there.

if test -e ./domains.sh; then
  . ./domains.sh
fi

export TTL SERIAL REFRESH RETRY EXPIRE NEGATIVE_CACHE_TTL SEVERITY TRANSFER \
    RECURSION RATE_LIMIT MAILSERVER NAMESERVER HOSTMASTER IPV6 DEFAULT_IP \
    DEFAULT_SUBDOMAINS DEFAULT_DOMAINS DOMAINS

exec /usr/bin/init --generate
