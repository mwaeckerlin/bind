#!/bin/bash -e

url=${1:-localhost}
port=${2:-$(test "$url" = "localhost" && echo 9953 || echo 53)}

# configure the same way as in docker-compose.yaml
DEFAULT_SUBDOMAINS="www test"
DEFAULT_IP="127.0.0.1"
DOMAINS='
          example.com
'

lookup() {
    nslookup -port=$port $1 $url | sed -n '/Non-authoritative answer:/{n;n;n};/^Name:/{n;s/Address:\s*//p}'
}
check() {
    response=$(lookup $1)
    if ! test "$response" = "$2"; then
        echo "*** ERROR $1 -> '$response' ≠ '$2'"
        fails+="\n*** ERROR $1 -> '$response' ≠ '$2'"
        return 1
    else
        echo "--- SUCCESS $1 -> '$response"
        return 0
    fi
}

IFS='
'
for test in $(sed 's/^\s*//'<<<"$DOMAINS"); do
    DOMAIN=${test%%=*}
    [[ $test =~ = ]] && IP=${test#*=} || IP=''
    IP=${IP%%;*}
    IP=${IP:-$DEFAULT_IP}
    [[ $test =~ \; ]] && SUBS=${test#*;} || SUBS=$DEFAULT_SUBDOMAINS
    SUBS=${SUBS%%;*}
    if check "$DOMAIN" "$IP"; then
        IFS=' '
        for sub in $SUBS; do
            SUB=${sub%%=*}
            [[ $sub =~ =A: ]] && SIP=${sub#*=A:} || SIP=$IP
            check $SUB.$DOMAIN $SIP || true
        done
    fi
done

echo
if test -z "$fails"; then
    echo "    #### ALL TESTS PASSED ####"
else
    echo "    **** SOME TESTS FAILED ****"
    echo -e "$fails"
    exit 1
fi