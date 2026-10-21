# the init writes the configuration, at build time and at start
FROM mwaeckerlin/very-base AS init
RUN $PKG_INSTALL g++
COPY init.cpp .
RUN g++ -static -Os -flto=auto -fno-rtti -ffunction-sections -fdata-sections \
        -Wl,--gc-sections -Wl,-s -std=c++20 -o init init.cpp
RUN strip -s -R .comment -R .gnu.version --strip-unneeded init

# build stage - configuration is done here
FROM mwaeckerlin/very-base AS named

# install packages
RUN mkdir /root/etc
RUN $PKG_INSTALL bind bind-tools
RUN chown root:$RUN_GROUP /etc/bind /var/bind /var/bind/dyn /var/bind/pri /var/bind/sec /var/run/named
COPY --from=init init /usr/bin/init
RUN mkdir -p /run/bind
RUN ${ALLOW_USER} /run/bind

# create /root with only the named executable, named-checkconf, the init,
# modules and dependencies, no configuration yet
RUN tar cph \
    /var/bind /var/run/named /run/bind /usr/sbin/named $(command -v named-checkconf) /usr/bin/init \
    $(for f in /usr/sbin/named $(command -v named-checkconf); do \
    ldd $f | sed -n 's,.* => \([^ ]*\) .*,\1,p'; \
    done 2> /dev/null) 2> /dev/null \
    | tar xpC /root/

# cache is invalidated where new arguments are used the first time
ARG EXPIRE
ARG MAILSERVER
ARG NEGATIVE_CACHE_TTL
ARG RATE_LIMIT
ARG RECURSION
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
ARG IPV6
ARG HOSTMASTER
ARG NAMESERVER

# build the configuration
COPY . /build
WORKDIR /build
RUN ./generate-configuration.sh
RUN named-checkconf -z /etc/bind/named.conf
RUN mv /etc/bind /root/etc/.
RUN mkdir -p /root/usr/share/bind
RUN mv /usr/share/bind/defaults /root/usr/share/bind/.


# now create a minimalistic image from scratch
FROM mwaeckerlin/scratch
EXPOSE 9953/udp
EXPOSE 9953/tcp
ENV CONTAINERNAME="bind"
ENTRYPOINT [ "/usr/bin/init" ]
COPY --from=named /root /
