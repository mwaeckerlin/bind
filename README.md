# Docker Image for flexible bind DNS Server

Configures a bind DNS server with IP address and MX records. On one hand, it is very easy to configure a large set of different URLs with common subdomains to the same IP address. On the other hand, it is flexible enough to handle special cases. It always adds a default MX record.

## Configuration

### Port

DNS service runs on port 53.

### Volumes

This image has no volumes.

### Variables

- `TTL`: time to live in seconds (default "3600")
- `SERIAL`: serial number (default generated from date and time)
- `REFRESH`: refresh value in seconds (default "3600")
- `RETRY`: retry value in seconds (default "1800")
- `EXPIRE`: expiry value in seconds (default "604800")
- `NEGATIVE_CACHE_TTL`: negative cache time to live in seconds (default "1800")
- `DEFAULT_IP`: required if default domains are given (default "")
- `DEFAULT_SUBDOMAINS`: subdomains to add to each default domain (default "*")
- `DEFAULT_DOMAINS`: list of domains to be configured with `DEFAULT_SUBDOMAINS` and `DEFAULT_IP` (default "")
- _`any.url`_: configure any non default url, here _http://any.url_; the value of the variable contains of semicolon separated parts:
    1. the IP address
    2. list of subdomains, if any subdomain points to a different IP address, just assign it with equal and prefix `A:`, to redirect to another domain, just assign the domain e.g. `-e any.url='123.45.67.89;abc www.main=A:12.34.56.78 dev=www.main def'` configures IP address `123.45.67.89` for `any.url`, `abc.any.url`, `def.any.url`, sets IP address `12.34.56.78` for `www.main.any.url` and sets `dev` as `CNAME` entry to `www.main`.
    3. all following semicolon separated lines that are added as is to the DNS record for full flexibility

### Examples

    docker run -d --restart unless-stopped --name bind -p 53:53/tcp -p 53:53/udp \
               -e 'domain1.com=123.45.67.89' \
               -e 'domain2.com=123.45.67.89' \
               -e 'domain3.com=123.45.67.89' \
               -e 'domain4.org=123.45.67.89;www something-else friendica lists=A:123.45.67.89 main www.main old.main dev.main=A:12.34.56.78 www.dev.main=A:12.34.56.78 *;@                   IN      TXT     "v=spf1 a mx ip4:123.45.67.89 ~all";lists               IN      MX 10   domain4.org.' \
               -e 'domain4.com=123.45.67.89;www main main www.main something-else friendica dev.main=dev.main.domain4.org. www.dev.main=dev.main.domain4.org.' \
               -e 'DEFAULT_IP=12.34.56.78' \
               -e 'DEFAULT_DOMAINS=domain5.com domain6.com' \
               mwaeckerlin/bind

This will create the following domain configuration files:

#### domain1.com domain2.com domain3.com

File `domain1.com` (and similar `domain2.com` `domain3.com`) are standard DNS entries configured according to the `DEFAULT_`-variables, but with a different IP address `123.45.67.89`:

    $TTL    3600
    @       IN      SOA     domain1.com. root.domain1.com. (
                            1494319633      ; Serial
                            3600    ; Refresh
                            1800    ; Retry
                            604800  ; Expire
                            1800 )  ; Negative Cache TTL
    ;
    @       IN      NS      @
    @       IN      A       123.45.67.89
    @       IN      MX 10   @
    *       IN      CNAME   @

#### domain4.org

File `domain4.org` has a special IP address to `123.45.67.89` plus special subdomains where `lists`, `dev.main` and `www.dev.main` have their own IP address `12.34.56.78`. The other subdomains `www`, `something-else`, `friendica`, `main`, `www.main`, `old.main` and `*` share the domains default IP address `123.45.67.89` and are therefore configured as `CNAME @`. Finally two special lines are appended: `@                   IN      TXT     "v=spf1 a mx ip4:123.45.67.89 ~all"` and `lists               IN      MX 10   domain4.org.`. This results in:

    $TTL    3600
    @       IN      SOA     domain4.org. root.domain4.org. (
                            1494328812      ; Serial
                            3600    ; Refresh
                            1800    ; Retry
                            604800  ; Expire
                            1800 )  ; Negative Cache TTL
    ;
    @       IN      NS      @
    @       IN      A       123.45.67.89
    @       IN      MX 10   @
    www     IN      CNAME   @
    something-else  IN      CNAME   @
    friendica       IN      CNAME   @
    lists   IN      A       123.45.67.89
    main    IN      CNAME   @
    www.main        IN      CNAME   @
    old.main        IN      CNAME   @
    dev.main        IN      A       12.34.56.78
    www.dev.main    IN      A       12.34.56.78
    *       IN      CNAME   @
    @                   IN      TXT     "v=spf1 a mx ip4:123.45.67.89 ~all"
    lists               IN      MX 10   domain4.org.

#### domain4.com

File `domain4.com` is very similar to `domain4.org`, except that there are no additional mails and `dev.main` and `www.dev.main` are set as `CNAME` to `dev.main.domain4.org`:

    $TTL    3600
    @       IN      SOA     domain4.com. root.domain4.com. (
                            1494319633      ; Serial
                            3600    ; Refresh
                            1800    ; Retry
                            604800  ; Expire
                            1800 )  ; Negative Cache TTL
    ;
    @       IN      NS      @
    @       IN      A       123.45.67.89
    @       IN      MX 10   @
    www     IN      CNAME   @
    main    IN      CNAME   @
    main    IN      CNAME   @
    www.main        IN      CNAME   @
    something-else  IN      CNAME   @
    friendica       IN      CNAME   @
    dev.main        IN      CNAME   dev.main.domain4.org.
    www.dev.main    IN      CNAME   dev.main.domain4.org.

#### domain5.com domain6.com

The files `domain5.com` and `domain6.com` are configured according to the defaults, so `domain5.com` is:

    $TTL    3600
    @       IN      SOA     domain5.com. root.domain5.com. (
                            1494328812      ; Serial
                            3600    ; Refresh
                            1800    ; Retry
                            604800  ; Expire
                            1800 )  ; Negative Cache TTL
    ;
    @       IN      NS      @
    @       IN      A       12.34.56.78
    @       IN      MX 10   @
    *       IN      CNAME   @
