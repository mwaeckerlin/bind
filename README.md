# Docker Image for flexible bind DNS Server

Configures a bind DNS server with IP address and MX records. On one hand, it is very easy to configure a large set of different URLs with common subdomains to the same IP address. On the other hand, it is flexible enough to handle special cases. It always adds a default MX record.

## Configuration

There are three methods how you can configure `mwaeckerlin/bind`, two at build time and one at run time:

  1. At build time, define variables in `domains.sh`
  2. At build time, define build arguments on command line or in `docker-compose.yaml`
  3. At runtime, just mount a volume containing your configuration to `/etc/bind`

*Note:* In previous versions of `mwaeckerlin/bind`, before 2023/01, the configuration was done on run-time, now configuration is done on build-time. This allows a smaller and much more secure docker image. But you must build `mwaeckerlin/bind` for your configuration on your own. Alternatively you may just mount a volume to `/etc/bind` with any arbitrary configuration.

### Port

DNS service runs on port 9953.

### Variables in `domains.sh` or as Build Arguments

- `TTL`: time to live in seconds (default "3600")
- `SERIAL`: serial number (default generated from date and time)
- `REFRESH`: refresh value in seconds (default "3600")
- `RETRY`: retry value in seconds (default "1800")
- `EXPIRE`: expiry value in seconds (default "604800")
- `NEGATIVE_CACHE_TTL`: negative cache time to live in seconds (default "1800")
- `TRANSFER`: IP address to allow DNS transfer (master to secondary)
- `DEFAULT_IP`: required if default domains are given (default "")
- `DEFAULT_SUBDOMAINS`: subdomains to add to each default domain (default "*")
- `DEFAULT_DOMAINS`: list of domains to be configured with `DEFAULT_SUBDOMAINS` and `DEFAULT_IP` (default "")
- `DOMAINS`: configure any non default url, where each domain must be on a single new line that is defined as:
    - _domain name_=_configuration, where _configuration is:
      - semicolon (`;`) separated and contains the followinf fields:
          1. the IP address
          2. space separated list of subdomains
             - if any subdomain points to a different IP address, just assign it with equal and prefix `A:`
          3. all following semicolon separated lines that are added as is to the DNS record for full flexibility
              - Use `\t` to insert a tabulator in self defined lines
 
### Examples

#### Simple Example

Default IP address is `12.34.56.78` and by default a prefix of `www` should be prepended. The subdomains `www` and `mail` should be defined, so domains `domain1.com`, `domain2.com`, `domain3.com` and `domain4.com` should include the subdomains `www.domain1.com` and `mail.domain1.com` for all domains and all names should go to the the default IP address.

For this either as build arguments or in `domains.sh` define the following variables:

    DEFAULT_IP='12.34.56.78'
    DEFAULT_SUBDOMAINS='www mail'
    DEFAULT_DOMAINS='1 domain2.com domain3.com domain4.com'

You can e.g. specify build arguments at command line:

    docker build --rm --force-rm \
        --build-arg DEFAULT_IP='12.34.56.78' \
        --build-arg DEFAULT_SUBDOMAINS='www mail' \
        --build-arg DEFAULT_DOMAINS='domain1.com domain2.com domain3.com domain4.com' \
        --tag my-bind .

Then run your image (I use port `9953` instead of `53` because I have another `named` running on my system):

    docker run -it --rm --name bind -p 9953:9953/udp my-bind

And test it using `dig` or `nslookup`, e.g.:

    nslookup -port=9953 mail.domain3.com - localhost
    dig @localhost -p 9953 www.domain4.com

The generated configuration file for `domain1.com` is in `/etc/bind/domain1.com` of the image and looks as follows:

```
$TTL    3600
@       IN      SOA     domain1.com. root.domain1.com. (
                        1674151173      ; Serial
                        3600    ; Refresh
                        1800    ; Retry
                        604800  ; Expire
                        1800 )  ; Negative Cache TTL
;
@       IN      NS      @
@       IN      A       12.34.56.78
@       IN      MX 10   @
www     IN      CNAME   @
mail    IN      CNAME   @
```

#### Complex Example

Now, in addition to the above default domain definitions, let's specify some special cases, we specify them in variable `DOMAINS`.

In addition to the example above, `domain5.com` should have a subdomain `www` and `lists` on the default IP address, but two other subdomains, `mail` and `test` should go to IP address `123.45.67.89`, and we want a `TXT` record that contains `"v=spf1 a mx ip4:123.45.67.89 ~all"` and for mailing lists, we want a subdomain `lists` with an `MX` record that points to `domain5.com`. Due to bind configuration rules, a `CNAME` record must not other data, such as `MX`, so you must change the entry for `lists` to an `A` record, even though it points to the master domain's IP address. You achieve this by writing: `lists=A:12.34.56.78`. And `domain6.com` should be like the default domains, just with another IP address of `123.45.67.89`. Use `\t` to insert a tabulator. So this results in trhe following definition, be aware, that the entries must be new line separated:

   DOMAINS='
        domain5.com=;www mail=A:123.45.67.89 test=A:123.45.67.89 lists=A:12.34.56.78;@\tIN\tTXT\t"v=spf1 a mx ip4:123.45.67.89 ~all";lists\tIN\tMX 10\tdomain5.com.
        domain6.com=123.45.67.89
    '

Again, build your image, don't forget the defaults from the example above:

    docker build --rm --force-rm \
        --build-arg DEFAULT_IP='12.34.56.78' \
        --build-arg DEFAULT_SUBDOMAINS='www mail' \
        --build-arg DEFAULT_DOMAINS='domain1.com domain2.com domain3.com domain4.com' \
        --build-arg DOMAINS='
                domain5.com=;www mail=A:123.45.67.89 test=A:123.45.67.89 lists=A:12.34.56.78;@\tIN\tTXT\t"v=spf1 a mx ip4:123.45.67.89 ~all";lists\tIN\tMX 10\tdomain5.com.
                domain6.com=123.45.67.89
            ' \
        --tag my-bind .

The generated configuration for `domain5.com` in file `/etc/bind/domain5.com` of the image looks as follows:

```
$TTL    3600
@       IN      SOA     domain5.com. root.domain5.com. (
                        1674169746      ; Serial
                        3600    ; Refresh
                        1800    ; Retry
                        604800  ; Expire
                        1800 )  ; Negative Cache TTL
;
@       IN      NS      @
@       IN      A       12.34.56.78
@       IN      MX 10   @
www     IN      CNAME   @
mail    IN      A       123.45.67.89
test    IN      A       123.45.67.89
lists   IN      A       12.34.56.78
@       IN      TXT     "v=spf1 a mx ip4:123.45.67.89 ~all"
lists   IN      MX 10   domain5.com.
```

#### Example in Docker Compose

The same example added to `docker-compose.yaml`:

```yaml
version: '3.3'
services:
  bind:
    build:
      context: .
      args:
        DEFAULT_IP: 12.34.56.78
        DEFAULT_SUBDOMAINS: www mail
        DEFAULT_DOMAINS: domain1.com domain2.com domain3.com domain4.com
        DOMAINS: |-
            domain5.com=;www mail=A:123.45.67.89 test=A:123.45.67.89 lists=A:12.34.56.78;@\tIN\tTXT\t"v=spf1 a mx ip4:123.45.67.89 ~all";lists\tIN\tMX 10\tdomain5.com.
            domain6.com=123.45.67.89
    image: mwaeckerlin/bind
    ports:
      - 9953:9953/udp
```