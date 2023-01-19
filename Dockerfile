# build stage - configuration is done here
FROM mwaeckerlin/very-base as named
ARG SERIAL
ARG TTL
ARG REFRESH
ARG RETRY
ARG EXPIRE
ARG NEGATIVE_CACHE_TTL
ARG TRANSFER
ARG SEVERITY
ARG DEFAULT_SUBDOMAINS
ARG DEFAULT_IP
ARG DEFAULT_DOMAINS
ARG DOMAINS
RUN $PKG_INSTALL bind bind-tools
RUN chown root.$RUN_GROUP /etc/bind /var/bind /var/bind/dyn /var/bind/pri /var/bind/sec /var/run/named 
RUN chown $RUN_USER.$RUN_GROUP /etc/bind/rndc.key
ADD . /build
WORKDIR /build
RUN ./generate-configuration.sh
RUN named-checkconf -z /etc/bind/named.conf
# /usr/share/dns-root-hints/named.root /usr/share/dns-root-hints/named.root 

# create /root with only the named executable, modules and dependencies:
RUN tar cph \
    /etc/bind /var/bind /var/run/named /usr/sbin/named \
    $(for f in /usr/sbin/named; do \
    ldd $f | sed -n 's,.* => \([^ ]*\) .*,\1,p'; \
    done 2> /dev/null) 2> /dev/null \
    | tar xpC /root/


# now create a minimalistic image from scratch
FROM mwaeckerlin/scratch
EXPOSE 9953/udp
ENV CONTAINERNAME "bind"
COPY --from=named /root /
ENTRYPOINT [ "/usr/sbin/named",  "-f", "-c", "/etc/bind/named.conf", "-L", "/dev/stdout" ]
