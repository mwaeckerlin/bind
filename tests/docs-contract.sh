#!/usr/bin/env bash
# Docs contract: the feature and test registers stay consistent, and tests
# are never skipped.
#
# FEATURES.md numbers every feature (`- **F<n> ...`), TESTS.md maps every test
# to the feature number it covers (`- **F<n>** ...`). This guard fails when:
#   1. a feature number is defined more than once in FEATURES.md,
#   2. a feature has no test entry in TESTS.md (untested feature),
#   3. TESTS.md references a feature number that does not exist,
#   4. a test file contains a skip/xfail marker — tests are never skipped.
#
# Usage: tests/docs-contract.sh

set -uo pipefail
cd "$(dirname "$0")/.."

PASS=0
FAIL=0
declare -a FAILED_NAMES

_pass() { PASS=$((PASS + 1)); echo "  PASS  $1"; }
_fail() { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); echo "  FAIL  $1: $2"; }

echo "==> Docs contract: feature/test registers"

for f in FEATURES.md TESTS.md; do
    if [[ -f "$f" ]]; then
        _pass "${f}_exists"
    else
        _fail "${f}_exists" "file missing"
    fi
done

if [[ -f FEATURES.md && -f TESTS.md ]]; then
    DEFINED=$(grep -oE '^- \*\*F[0-9]+' FEATURES.md | grep -oE 'F[0-9]+')
    REFERENCED=$(grep -oE '^- \*\*F[0-9]+' TESTS.md | grep -oE 'F[0-9]+' | sort -u)

    DUPES=$(echo "${DEFINED}" | sort | uniq -d | tr '\n' ' ')
    if [[ -n "${DUPES// /}" ]]; then
        _fail "unique_feature_numbers" "defined more than once: ${DUPES}"
    else
        _pass "unique_feature_numbers"
    fi

    UNTESTED=""
    for n in ${DEFINED}; do
        echo "${REFERENCED}" | grep -qx "${n}" || UNTESTED="${UNTESTED} ${n}"
    done
    if [[ -n "${UNTESTED}" ]]; then
        _fail "every_feature_tested" "no test entry for:${UNTESTED}"
    else
        _pass "every_feature_tested"
    fi

    UNDEFINED=""
    for n in ${REFERENCED}; do
        echo "${DEFINED}" | grep -qx "${n}" || UNDEFINED="${UNDEFINED} ${n}"
    done
    if [[ -n "${UNDEFINED}" ]]; then
        _fail "no_dangling_references" "TESTS.md references unknown:${UNDEFINED}"
    else
        _pass "no_dangling_references"
    fi
fi

# every variable the init reads is a build argument, is handed over by
# generate-configuration.sh and is documented in the README
VARIABLES=$(sed -n '/^const std::vector<std::string> VARIABLES/,/};/p' init.cpp | grep -oE '"[A-Z_0-9]+"' | tr -d '"')
if [[ -z "${VARIABLES}" ]]; then
    _fail "variables_found" "no VARIABLES list in init.cpp"
fi
for v in ${VARIABLES}; do
    grep -qx "ARG ${v}" Dockerfile || _fail "build_argument_${v}" "no ARG ${v} in Dockerfile"
    grep -qw "${v}" generate-configuration.sh || _fail "handed_over_${v}" "generate-configuration.sh does not export ${v}"
    if grep -q "^- \`${v}\`:" README.md; then
        _pass "documented_${v}"
    else
        _fail "documented_${v}" "README.md has no entry for ${v}"
    fi
done

SKIPS=$(grep -rnE 'pytest\.mark\.skip|skipif|xfail|pytest\.skip\(' tests/e2e --include='*.py' 2>/dev/null)
if [[ -n "${SKIPS}" ]]; then
    _fail "no_skipped_tests" "skip/xfail markers found: ${SKIPS}"
else
    _pass "no_skipped_tests"
fi

echo ""
echo "==> Docs contract results: ${PASS} passed, ${FAIL} failed"
if [[ ${FAIL} -gt 0 ]]; then
    echo "==> Failed contracts: ${FAILED_NAMES[*]}"
    exit 1
fi
