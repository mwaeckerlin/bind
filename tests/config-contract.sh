#!/usr/bin/env bash
# Config contract: the shipped configuration is production-safe, and a
# configuration that is not a configuration never becomes an image.
#
# The server must answer for its own zones only, must not offer them to
# anybody, must not name its version and must have no remote control channel.
# The checks read the configuration out of the shipped image instead of
# building it again, so they measure the artefact that would be deployed.
#
# A variable given at start makes the init write the configuration again, from
# that value and the values of the build; its result is copied out of a
# started container, and a value that would break out of its line is refused.
#
# A domain name that is not a domain name is written into a file name and into
# the server configuration, so the build must refuse it. That refusal is
# measured with builds that must fail, and with one that must succeed —
# otherwise a build that fails for any other reason would look like a pass.
#
# Usage: tests/config-contract.sh IMAGE

set -uo pipefail
cd "$(dirname "$0")/.."

IMAGE="${1:?usage: tests/config-contract.sh IMAGE}"

PASS=0
FAIL=0
declare -a FAILED_NAMES

_pass() { PASS=$((PASS + 1)); echo "  PASS  $1"; }
_fail() { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); echo "  FAIL  $1: $2"; }

_file() { # <path in the image>
    local container output
    container=$(docker create "${IMAGE}") || return 1
    output=$(docker export "${container}" | tar -xO "$1" 2>/dev/null)
    docker rm "${container}" > /dev/null
    echo "${output}"
}

_holds() { # <content> <pattern> <name> <reason>
    if echo "$1" | grep -Eq -- "$2"; then
        _pass "${IMAGE}_$3"
    else
        _fail "${IMAGE}_$3" "$4"
    fi
}

_build() { # <domains> — prints the build output, returns the build status
    docker build --progress plain --file Dockerfile --target named \
        --build-arg DEFAULT_IP=10.0.0.1 \
        --build-arg DEFAULT_SUBDOMAINS=www \
        --build-arg DOMAINS="$1" \
        --tag "${IMAGE}-config-contract" . 2>&1
}

_refused() { # <name> <domains>
    local output
    output=$(_build "$2")
    if [[ $? -eq 0 ]]; then
        _fail "refuses_$1" "the build succeeded"
    elif ! echo "${output}" | grep -q 'invalid domain name'; then
        _fail "refuses_$1" "the build failed for another reason: $(echo "${output}" | tail -3)"
    else
        _pass "refuses_$1"
    fi
}

echo "==> Config contract: production-safe bind"

if ! docker image inspect "${IMAGE}" > /dev/null 2>&1; then
    _fail "${IMAGE}_image_exists" "image not built — run 'npm run build' first"
else
    CONFIG=$(_file etc/bind/named.conf)
    _holds "${CONFIG}" '^[[:space:]]*recursion no;$' recursion_off \
        "the server would resolve foreign names for anybody"
    _holds "${CONFIG}" '^[[:space:]]*allow-transfer \{ none; \};$' no_transfer \
        "the zones would be offered for transfer by default"
    _holds "${CONFIG}" '^[[:space:]]*version none;$' version_hidden \
        "the server would name its bind version"
    _holds "${CONFIG}" '^controls \{ \};$' no_control_channel \
        "the server would offer a remote control channel"
    _holds "${CONFIG}" '^[[:space:]]*listen-on port 9953' service_port \
        "the server would listen somewhere else than on port 9953"

    _holds "${CONFIG}" '^[[:space:]]*listen-on-v6 \{ none; \};$' ipv6_default \
        "without IPV6 the server would listen on IPv6"

    LOCAL=$(_file etc/bind/named.conf.local)
    _holds "${LOCAL}" '^zone "[^"]+" \{$' zones_configured \
        "the image carries no zone at all"
    _holds "${LOCAL}" '^[[:space:]]*type master;$' master_zones \
        "the zones are not master zones"

    FIRST=$(echo "${LOCAL}" | sed -n 's/^zone "\([^"]*\)" {$/\1/p' | head -1)
    ZONE=$(_file "etc/bind/${FIRST}")
    _holds "${ZONE}" "^@[[:space:]]+IN[[:space:]]+SOA[[:space:]]+${FIRST//./\\.}\. root\.${FIRST//./\\.}\. \($" \
        hostmaster_default "without HOSTMASTER the mailbox is not root.<domain>"
    _holds "${ZONE}" '^@[[:space:]]+IN[[:space:]]+NS[[:space:]]+@$' \
        nameserver_default "without NAMESERVER the domain is not its own name server"
fi

echo "==> Config contract: the configuration comes from domains.sh too"

# The build stage still has a shell and the generator, so the file path is
# measured by writing a domains.sh and letting the generator run — the build
# arguments are measured by every service of the e2e stack.
BUILDER="${IMAGE}-config-contract"
if ! docker build --progress quiet --file Dockerfile --target named \
        --build-arg DEFAULT_IP=10.0.0.1 --build-arg DOMAINS=good.example \
        --build-arg IPV6=any --build-arg HOSTMASTER=hostmaster.example.com \
        --build-arg NAMESERVER=ns1.example.com \
        --tag "${BUILDER}" . > /dev/null 2>&1; then
    _fail "builds_the_generator" "the build stage does not build"
else
    # the three build arguments reach the configuration the build moved to /root
    BUILT=$(docker run --rm --entrypoint cat "${BUILDER}" \
        /root/etc/bind/named.conf /root/etc/bind/good.example 2>&1)
    _holds "${BUILT}" '^[[:space:]]*listen-on-v6 port 9953 \{ any; \};$' \
        ipv6_from_build_argument "IPV6 did not reach the configuration"
    _holds "${BUILT}" '^@[[:space:]]+IN[[:space:]]+SOA[[:space:]]+good\.example\. hostmaster\.example\.com\. \($' \
        hostmaster_from_build_argument "HOSTMASTER did not reach the zone"
    _holds "${BUILT}" '^@[[:space:]]+IN[[:space:]]+NS[[:space:]]+ns1\.example\.com\.$' \
        nameserver_from_build_argument "NAMESERVER did not reach the zone"

    # the build moved the generated configuration out of /etc/bind into the
    # image it ships, so the directory is created again for this run
    GENERATED=$(docker run --rm --entrypoint sh "${BUILDER}" -c '
        printf "%s\n" "DEFAULT_IP=10.2.0.1" "DEFAULT_SUBDOMAINS=www" \
            "MAILSERVER=mail.example.com" "DOMAINS=file.example" > domains.sh
        mkdir -p /etc/bind
        ./generate-configuration.sh > /dev/null 2>&1
        cat /etc/bind/file.example' 2>&1)
    _holds "${GENERATED}" '^@[[:space:]]+IN[[:space:]]+A[[:space:]]+10\.2\.0\.1$' \
        address_from_domains_sh "the address in domains.sh did not reach the zone"
    _holds "${GENERATED}" '^@[[:space:]]+IN[[:space:]]+MX 10[[:space:]]+mail\.example\.com\.$' \
        mailserver_from_domains_sh "the mail server in domains.sh did not reach the zone"
    _holds "${GENERATED}" '^www[[:space:]]+IN[[:space:]]+CNAME[[:space:]]+@$' \
        subdomains_from_domains_sh "the subdomains in domains.sh did not reach the zone"
fi

echo "==> Config contract: the configuration comes from the environment at start"

# The image has no shell, so the configuration a container wrote at start is
# copied out of it; the container is started without a network, which is all
# the init needs to write it.
_started() { # <file in /run/bind> <docker run options...> — prints the file
    local file="$1" container output
    shift
    container=$(docker run -d --network none "$@" "${IMAGE}") || return 1
    for _ in $(seq 30); do
        output=$(docker cp "${container}:/run/bind/${file}" - 2>/dev/null | tar -xO 2>/dev/null)
        [[ -n "${output}" ]] && break
        sleep 1
    done
    docker rm -fv "${container}" > /dev/null 2>&1
    echo "${output}"
}

_refused_at_start() { # <name> <variable> <value> [<message>]
    local output status message="${4:-invalid $2}"
    output=$(timeout 60 docker run --rm --network none -e DOMAINS=env.example \
        -e DEFAULT_IP=10.3.0.1 -e "$2=$3" "${IMAGE}" 2>&1)
    status=$?
    if [[ ${status} -eq 0 || ${status} -eq 124 ]]; then
        _fail "refuses_at_start_$1" "the server started with $2='$3'"
    elif ! echo "${output}" | grep -q "${message}"; then
        _fail "refuses_at_start_$1" "it failed for another reason: $(echo "${output}" | tail -3)"
    else
        _pass "refuses_at_start_$1"
    fi
}

DEFAULTS_CONF=$(_started named.conf -e DOMAINS=env.example -e DEFAULT_IP=10.3.0.1)
DEFAULTS_ZONE=$(_started env.example -e DOMAINS=env.example -e DEFAULT_IP=10.3.0.1)
_holds "${DEFAULTS_ZONE}" '^@[[:space:]]+IN[[:space:]]+A[[:space:]]+10\.3\.0\.1$' \
    domains_from_environment "DOMAINS and DEFAULT_IP at start did not reach the zone"
_holds "${DEFAULTS_CONF}" '^[[:space:]]*recursion no;$' environment_recursion_off \
    "the configuration written at start resolves foreign names"
_holds "${DEFAULTS_CONF}" '^[[:space:]]*listen-on-v6 \{ none; \};$' environment_ipv6_default \
    "without IPV6 the configuration written at start listens on IPv6"
_holds "${DEFAULTS_ZONE}" '^@[[:space:]]+IN[[:space:]]+SOA[[:space:]]+env\.example\. root\.env\.example\. \($' \
    environment_hostmaster_default "without HOSTMASTER the mailbox is not root.<domain>"
_holds "${DEFAULTS_ZONE}" '^@[[:space:]]+IN[[:space:]]+NS[[:space:]]+@$' \
    environment_nameserver_default "without NAMESERVER the domain is not its own name server"

OVERRIDES=(-e DOMAINS=env.example -e DEFAULT_IP=10.3.0.1 -e IPV6=any
    -e HOSTMASTER=hostmaster.example.com -e NAMESERVER=ns1.example.com)
_holds "$(_started named.conf "${OVERRIDES[@]}")" \
    '^[[:space:]]*listen-on-v6 port 9953 \{ any; \};$' \
    ipv6_from_environment "IPV6 at start did not reach the configuration"
OVERRIDDEN_ZONE=$(_started env.example "${OVERRIDES[@]}")
_holds "${OVERRIDDEN_ZONE}" '^@[[:space:]]+IN[[:space:]]+SOA[[:space:]]+env\.example\. hostmaster\.example\.com\. \($' \
    hostmaster_from_environment "HOSTMASTER at start did not reach the zone"
_holds "${OVERRIDDEN_ZONE}" '^@[[:space:]]+IN[[:space:]]+NS[[:space:]]+ns1\.example\.com\.$' \
    nameserver_from_environment "NAMESERVER at start did not reach the zone"

_refused_at_start ttl_with_a_directive  TTL        '1; };'
_refused_at_start severity_unknown      SEVERITY   'loud'
_refused_at_start recursion_with_brace  RECURSION  'any; }; allow-transfer { any'
_refused_at_start ipv6_with_a_line      IPV6       $'any;\n};'
_refused_at_start hostmaster_with_space HOSTMASTER 'host master.example.com'
_refused_at_start nameserver_with_quote NAMESERVER 'ns1".example.com'
_refused_at_start domain_name_path      DOMAINS    '../../etc/passwd' 'invalid domain name'

echo "==> Config contract: an invalid domain name stops the build"

OUTPUT=$(_build 'good.example')
if [[ $? -eq 0 ]]; then
    _pass "accepts_an_ordinary_name"
else
    _fail "accepts_an_ordinary_name" "the build failed: $(echo "${OUTPUT}" | tail -3)"
fi
_refused a_path                '../../etc/passwd'
_refused a_name_with_a_space   'two words.example'
_refused a_name_with_a_quote   'quote".example'
_refused a_name_with_two_dots  'double..example'

docker image rm -f "${BUILDER}" > /dev/null 2>&1

echo ""
echo "==> Config contract results: ${PASS} passed, ${FAIL} failed"
if [[ ${FAIL} -gt 0 ]]; then
    echo "==> Failed contracts: ${FAILED_NAMES[*]}"
    exit 1
fi
