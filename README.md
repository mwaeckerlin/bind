# Docker Image for flexible bind DNS Server

Configures a bind DNS server with IP address and MX records. On one hand, it is very easy to configure a large set of different URLs with common subdomains to the same IP address. On the other hand, it is flexible enough to handle special cases. It always adds a default MX record.

The image is minimised and secured: There is no shell and nothing but the bind executable its dependencies and the configurations in the image. Image size is only 17MB (subject to change from build to build). The bind executable is copied from the Alpine distribution and maintained there.

## Configuration

There are three methods how you can configure `mwaeckerlin/bind`, two at build time and one at run time:

1. At build time, define variables in `domains.sh`
2. At build time, define build arguments on command line or in `docker-compose.yaml`
3. At runtime, just mount a volume containing your configuration to `/etc/bind`

_Note:_ In previous versions of `mwaeckerlin/bind`, before 2023/01, the configuration was done on run-time, now configuration is done on build-time. This allows a smaller and much more secure docker image. But you must build `mwaeckerlin/bind` for your configuration on your own. Alternatively you may just mount a volume to `/etc/bind` with any arbitrary configuration.

### Port

DNS service runs on port 9953, over UDP and over TCP. The unprivileged port lets the container run beside a `named` of the host; TCP is what a client falls back to when an answer does not fit into one datagram, and it is the transport of a zone transfer.

### Security

The generated configuration is hardened for an authoritative-only server:

- **No recursion:** `recursion no` — the server only answers for its own zones and never resolves foreign names, so it cannot be abused as an open resolver or for amplification.
- **No zone transfers by default:** `allow-transfer { none; }` globally; a transfer is only allowed for the zones and the address given in `TRANSFER`. Trade-off: if you operate a secondary DNS server, you must set `TRANSFER`, otherwise it will not receive the zones.
- **No version disclosure:** `version none` — queries for `version.bind` are refused.
- **No control channel:** `controls { }` and the generated `rndc.key` is removed, so no secret key ends up in the image layers; the server is controlled through container signals only.
- **Validated input:** domain names from `DOMAINS`/`DEFAULT_DOMAINS` are validated at build time before they are rendered into file names and the bind configuration.
- **Minimal non-root image:** the final image contains only `named` and its libraries (no shell, no interpreter, no package manager), built `FROM mwaeckerlin/scratch`, which runs as an unprivileged user.

Since the image is built from the rolling latest Alpine bind package, rebuild and redeploy regularly to pick up bind security fixes.

### Variables in `domains.sh` or as Build Arguments

- `TTL`: time to live in seconds (default "3600")
- `SERIAL`: serial number (default generated from date and time)
- `REFRESH`: refresh value in seconds (default "3600")
- `RETRY`: retry value in seconds (default "1800")
- `EXPIRE`: expiry value in seconds (default "604800")
- `NEGATIVE_CACHE_TTL`: negative cache time to live in seconds (default "1800")
- `TRANSFER`: IP address to allow DNS transfer (master to secondary)
- `SEVERITY`: how much the server logs to standard output, one of `critical`, `error`, `warning`, `notice`, `info`, `debug` (default "warning"); `info` logs a line per query, which is what you want while you hunt a problem and not in normal operation
- `MAILSERVER`: your mailserver for the `MX` record, set this variable, if all domains have the same mail server (default "@", means same name as domain)
- `DEFAULT_IP`: required if default domains are given (default "")
- `DEFAULT_SUBDOMAINS`: subdomains to add to each default domain (default "\*")
- `DEFAULT_DOMAINS`: list of domains to be configured with `DEFAULT_SUBDOMAINS` and `DEFAULT_IP` (default "")
- `DOMAINS`: configure any non default url, where each domain must be on a single new line that is defined as:
  - _domain name_=\_configuration, where \_configuration is:
  - semicolon (`;`) separated and contains the following fields:
    1. the IP address
    2. space separated list of subdomains
       - if any subdomain points to a different IP address, just assign it with equal and prefix `A:`
    3. all following semicolon separated lines that are added as is to the DNS record for full flexibility
       - Use `\t` to insert a tabulator in self defined lines
  - example: `domain.com=12.34.56.78;www mail` uses IP address `12.34.56.78` for domain `domain.com` and generates subdomains `www.domain.com` and `mail.domain.com`

### Examples

#### Simple Example

Default IP address is `12.34.56.78` and by default a prefix of `www` should be prepended. The subdomains `www` and `mail` should be defined, so domains `domain1.com`, `domain2.com`, `domain3.com` and `domain4.com` should include the subdomains `www.domain1.com` and `mail.domain1.com` for all domains and all names should go to the the default IP address.

For this either as build arguments or in `domains.sh` define the following variables:

    DEFAULT_IP='12.34.56.78'
    DEFAULT_SUBDOMAINS='www mail'
    DEFAULT_DOMAINS='domain1.com domain2.com domain3.com domain4.com'

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
version: "3.3"
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

## Build, run, test

Everything runs through the scripts in `package.json`:

    npm run build            build the image from docker-compose.yaml
    npm start                build it and run the container in the foreground
    npm run start:daemon     the same in the background
    npm stop                 stop the container and remove it
    npm test                 run every test of this project

`npm test` runs four groups, each also available on its own:

- `npm run test:docs` — every feature carries a test and no test is skipped
- `npm run test:image` — the delivered image is headless, unprivileged and carries no key
- `npm run test:config` — the shipped configuration is production-safe, `domains.sh` is read, an invalid domain name stops the build
- `npm run test:e2e` — four servers are built and asked: the configuration of this repository, the defaults, every variable with a value of its own, and a configuration mounted at run time

The same questions go to a deployed server, which is how a deployment is checked after the fact:

    npm run test:server -- ns1.example.com
    ./test.sh ns1.example.com 53

The tests read the configuration from `docker-compose.yaml`, so they always measure the configuration this repository describes and never a second copy of it.

[FEATURES.md](FEATURES.md) lists what the image does, [TESTS.md](TESTS.md) which test covers which feature.
