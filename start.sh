#! /bin/bash

rm /etc/bind/named.conf.local

set -f
IFS="
"
for line in $(env | egrep '^[-.0-9a-z]*=') $(echo ${DEFAULT_DOMAINS} | tr ' ' '\n'); do
    base=${line%%=*}
    [[ $line =~ = ]] && args=${line#*=} || args=''
    ip=${args%%;*}
    [[ $args =~ \; ]] && args=${args#*;} || args=''
    subs=${args%%;*}
    [[ $args =~ \; ]] && args=${args#*;} || args=''
    echo "... domain: $base"
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
@	IN	A	${ip:-${DEFAULT_IP}}
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
    cat >> /etc/bind/named.conf.local <<EOF
zone "${base}" {
	type master;
	allow-query { any; };
	file "/etc/bind/$base";
};
EOF
done

echo "ready."
named -f
