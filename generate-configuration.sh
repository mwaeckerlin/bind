#!/bin/sh -e

if test -e ./domains.sh; then
  . ./domains.sh
fi

# required default values
TTL=${TTL:-'3600'}
REFRESH=${REFRESH:-'3600'}
RETRY=${RETRY:-'1800'}
EXPIRE=${EXPIRE:-'604800'}
NEGATIVE_CACHE_TTL=${NEGATIVE_CACHE_TTL:-'1800'}
SEVERITY=${SEVERITY:-'warning'}
DEFAULT_SUBDOMAINS=${DEFAULT_SUBDOMAINS:-'*'}

! test -e /etc/bind/named.conf.local || rm /etc/bind/named.conf.local

cat >> /etc/bind/named.conf <<EOF
logging {
  channel simplelog {
    stderr;
    severity ${SEVERITY};
    print-category yes;
    print-severity yes;
    print-time yes;
  };
  category default { simplelog; };
  category general { simplelog; };
  category config { simplelog; };
  category network { simplelog; };
  category queries { simplelog; };
  category security { simplelog; };
};

options {
  directory "/var/bind";
  pid-file "/var/run/named/named.pid";
  listen-on port 9953 { any; };
  listen-on-v6 { none; };
};

include "/etc/bind/named.conf.local";

EOF

set -f
IFS="
"
for line in \
    $(echo -e "${DOMAINS}" | sed 's/^\s*//') \
    $(echo ${DEFAULT_DOMAINS} | tr ' ' '\n');
do
    base=${line%%=*}
    [ "${line/=/}" != "${line}" ] && args=${line#*=} || args="${DEFAULT_IP}"
    ip=${args%%;*}
    ip=${ip:-${DEFAULT_IP}}
    [ "${args/;/}" != "${args}" ] && args=${args#*;} || args=''
    subs=${args%%;*}
    [ "${args/;/}" != "${args}" ] && args=${args#*;} || args=''
    echo "... domain: $base -> $ip"
    cat > "/etc/bind/$base" <<EOF
\$TTL	${TTL}
@	IN	SOA	${base}. root.${base}. (
			${SERIAL:-$(date +%s)}	; Serial
			${REFRESH}	; Refresh
			${RETRY}	; Retry
			${EXPIRE}	; Expire
			${NEGATIVE_CACHE_TTL} )	; Negative Cache TTL
;
@	IN	NS	@
@	IN	A	${ip}
@	IN	MX 10	@
EOF
    IFS=" "
    for sub in ${subs:-${DEFAULT_SUBDOMAINS}}; do
        [ "${sub/=/}" != "${sub}" ] && addr=${sub#*=} || addr=''
        [ "${addr/:/}" != "${addr}" ] && t=${addr%%:*} || t=''
        addr=${addr#*:}
        cat >> "/etc/bind/$base" <<EOF
${sub%%=*}	IN	${t:-CNAME}	${addr:-@}
EOF
    done
    IFS=';'
    for rec in $args; do
        cat >> "/etc/bind/$base" <<EOF
$(echo "$rec" | sed 's/\\t/\t/g')
EOF
    done
    cat >> /etc/bind/named.conf.local <<EOF
zone "${base}" {
	type master;
	allow-query { any; };
EOF
    if test -n "$TRANSFER"; then
        cat >> /etc/bind/named.conf.local <<EOF
	notify yes;
	also-notify { ${TRANSFER%;}; };
	allow-transfer { ${TRANSFER%;}; };
EOF
    fi
    cat >> /etc/bind/named.conf.local <<EOF
	file "/etc/bind/$base";
};
EOF
    if ! named-checkzone "$base" "/etc/bind/$base"; then
        cat /etc/bind/$base
        exit 1
    fi
done