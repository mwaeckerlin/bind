#!/usr/bin/env bash
# Image contract: every shipped image must be headless and carry no secret.
#
# A production image must contain nothing that lets an attacker who reaches
# code execution pivot: no shell, no perl, no busybox. The image ships the
# service binary, its libraries and its configuration — nothing else. The
# control key that bind generates must be gone, otherwise a secret lies in an
# image layer of a public image.
#
# The interpreter checks run the interpreter as the container entrypoint
# instead of asking the image to look at its own filesystem: a headless image
# has no `ls` either, so a missing tool must be detected from outside. What is
# in the image is read by exporting it. `--pull=never` keeps docker from
# silently pulling a stale image from the registry when the local build is
# missing; that would test the wrong artefact.
#
# Usage: tests/image-contract.sh IMAGE...

set -uo pipefail

PASS=0
FAIL=0
declare -a FAILED_NAMES

_pass() { PASS=$((PASS + 1)); echo "  PASS  $1"; }
_fail() { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); echo "  FAIL  $1: $2"; }

# Absence of the interpreter is the pass condition, so the image itself must be
# present — otherwise every check would "pass" on a nonexistent image.
_image_exists() {
    local image="$1"
    if docker image inspect "${image}" > /dev/null 2>&1; then
        return 0
    fi
    _fail "${image}_image_exists" "image not built — run 'npm run build' first"
    return 1
}

_no_interpreter() {
    local image="$1" path="$2" name="$3"
    shift 3
    if docker run --rm --pull=never --entrypoint "${path}" "${image}" "$@" > /dev/null 2>&1; then
        _fail "${image}_no_${name}" "${path} exists — image is not headless"
    else
        _pass "${image}_no_${name}"
    fi
}

_contents() {
    local container
    container=$(docker create "$1") || return 1
    docker export "${container}" | tar -t
    docker rm "${container}" > /dev/null
}

_holds() {
    local image="$1" path="$2" name="$3"
    if echo "${CONTENTS}" | grep -qx "${path}"; then
        _pass "${image}_${name}"
    else
        _fail "${image}_${name}" "${path} is not in the image"
    fi
}

_holds_not() {
    local image="$1" path="$2" name="$3"
    if echo "${CONTENTS}" | grep -qx "${path}"; then
        _fail "${image}_${name}" "${path} is in the image"
    else
        _pass "${image}_${name}"
    fi
}

_inspect() {
    local image="$1" format="$2" expected="$3" name="$4" actual
    actual=$(docker inspect --format "${format}" "${image}")
    if [[ "${actual}" == "${expected}" ]]; then
        _pass "${image}_${name}"
    else
        _fail "${image}_${name}" "${actual} instead of ${expected}"
    fi
}

echo "==> Image contract: headless images"

for image in "$@"; do
    _image_exists "${image}" || continue
    _no_interpreter "${image}" /bin/sh      sh      -c :
    _no_interpreter "${image}" /bin/bash    bash    -c :
    _no_interpreter "${image}" /bin/busybox busybox ls /
    _no_interpreter "${image}" /usr/bin/perl perl   -e 1

    CONTENTS=$(_contents "${image}")
    _holds     "${image}" usr/sbin/named       holds_the_server
    _holds     "${image}" etc/bind/named.conf  holds_the_configuration
    _holds_not "${image}" etc/bind/rndc.key    no_control_key
    _holds_not "${image}" sbin/apk             no_package_manager

    _inspect "${image}" '{{.Config.User}}' somebody unprivileged_user
    _inspect "${image}" '{{.Config.ExposedPorts}}' 'map[9953/tcp:{} 9953/udp:{}]' service_ports
done

echo ""
echo "==> Image contract results: ${PASS} passed, ${FAIL} failed"
if [[ ${FAIL} -gt 0 ]]; then
    echo "==> Failed contracts: ${FAILED_NAMES[*]}"
    exit 1
fi
