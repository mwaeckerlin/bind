#! /bin/bash

if test -e /letsencrypt-config.sh; then
    . /letsencrypt-config.sh
fi

rm /etc/bind/named.conf.local

declare -A domains

set -f
IFS="
"
for line in $(env | egrep '^[-.0-9a-z]*=') $(echo ${DEFAULT_DOMAINS} | tr ' ' '\n'); do
    base=${line%%=*}
    [[ $line =~ = ]] && args=${line#*=} || args="${DEFAULT_IP}"
    ip=${args%%;*}
    ip=${ip:-${DEFAULT_IP}}
    [[ $args =~ \; ]] && args=${args#*;} || args=''
    subs=${args%%;*}
    [[ $args =~ \; ]] && args=${args#*;} || args=''
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
        [[ $sub =~ = ]] && addr=${sub#*=} || addr=''
        [[ $addr =~ : ]] && t=${addr%%:*} || t=''
        addr=${addr#*:}
        cat >> "/etc/bind/$base" <<EOF
${sub%%=*}	IN	${t:-CNAME}	${addr:-@}
EOF
    done
    IFS=';'
    for rec in $args; do
        cat >> "/etc/bind/$base" <<EOF
$rec
EOF
    done
    domains[$base]="${subs:-${DEFAULT_SUBDOMAINS}}"
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
    named-checkzone "$base" "/etc/bind/$base"
done

if test "${LETSENCRYPT}" != "off"; then
    echo "... setup certificates"
    named
    for d in ${!domains[@]}; do
        installcerts $d "${domains[$d]}"
    done
    echo "ready."
    /start.letsencrypt.sh
    sleep infinity
else
    echo "ready."
    named -f -L /dev/stdout -d 6
fi
