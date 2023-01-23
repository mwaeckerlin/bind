# build stage - configuration is done here
FROM mwaeckerlin/very-base as named

# install packages
RUN mkdir /root/etc
RUN $PKG_INSTALL bind bind-tools
RUN chown root.$RUN_GROUP /etc/bind /var/bind /var/bind/dyn /var/bind/pri /var/bind/sec /var/run/named 
RUN chown $RUN_USER.$RUN_GROUP /etc/bind/rndc.key

# create /root with only the named executable, modules and dependencies, no configuration yet
RUN tar cph \
    /var/bind /var/run/named /usr/sbin/named \
    $(for f in /usr/sbin/named; do \
    ldd $f | sed -n 's,.* => \([^ ]*\) .*,\1,p'; \
    done 2> /dev/null) 2> /dev/null \
    | tar xpC /root/

# cache is invalidated where new arguments are used the first time
ARG EXPIRE
ARG NEGATIVE_CACHE_TTL
ARG REFRESH
ARG RETRY
ARG SERIAL
ARG SEVERITY
ARG TRANSFER
ARG TTL
ARG DEFAULT_IP
ARG DEFAULT_SUBDOMAINS
ARG DEFAULT_DOMAINS
ARG DOMAINS

# build the configuration
COPY . /build
WORKDIR /build
RUN ./generate-configuration.sh
RUN named-checkconf -z /etc/bind/named.conf
RUN mv /etc/bind /root/etc/.


# now create a minimalistic image from scratch
FROM mwaeckerlin/scratch
EXPOSE 9953/udp
EXPOSE 9953/tcp
ENV CONTAINERNAME "bind"
ENTRYPOINT [ "/usr/sbin/named",  "-f", "-c", "/etc/bind/named.conf", "-L", "/dev/stdout" ]
COPY --from=named /root /
