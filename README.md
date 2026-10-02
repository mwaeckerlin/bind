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

### Variables in `domains.sh` or as Build Arguments

- `TTL`: time to live in seconds (default "3600")
- `SERIAL`: serial number (default generated from date and time)
- `REFRESH`: refresh value in seconds (default "3600")
- `RETRY`: retry value in seconds (default "1800")
- `EXPIRE`: expiry value in seconds (default "604800")
- `NEGATIVE_CACHE_TTL`: negative cache time to live in seconds (default "1800")
- `TRANSFER`: IP address to allow DNS transfer (master to secondary), default "" — no transfer at all; see [Handing the zones to a secondary](#handing-the-zones-to-a-secondary-transfer)
- `RECURSION`: who may have foreign names looked up here — an address, a network, a bind address list, or `any` (default "", the server answers for its own zones only); read [Looking foreign names up](#looking-foreign-names-up-recursion) before you set it
- `RATE_LIMIT`: identical answers per second per client prefix (default "", no limit); recommended `10` on a public server, see [The limit on identical answers](#the-limit-on-identical-answers-rate_limit)
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
- `npm run test:e2e` — five servers are built and asked: the configuration of this repository, the defaults, every variable with a value of its own, a configuration mounted at run time, and one that resolves foreign names under a rate limit

The same questions go to a deployed server, which is how a deployment is checked after the fact:

    npm run test:server -- ns1.example.com
    ./test.sh ns1.example.com 53

The tests read the configuration from `docker-compose.yaml`, so they always measure the configuration this repository describes and never a second copy of it.

## Security

The generated configuration is hardened for an authoritative-only server:

- **No recursion:** `recursion no` — the server only answers for its own zones and never resolves foreign names, so it cannot be abused as an open resolver or for amplification.
- **No zone transfers by default:** `allow-transfer { none; }` globally; a transfer is only allowed for the zones and the address given in `TRANSFER`. Trade-off: if you operate a secondary DNS server, you must set `TRANSFER`, otherwise it will not receive the zones.
- **No version disclosure:** `version none` — queries for `version.bind` are refused.
- **No control channel:** `controls { }` and the generated `rndc.key` is removed, so no secret key ends up in the image layers; the server is controlled through container signals only.
- **Validated input:** domain names from `DOMAINS`/`DEFAULT_DOMAINS` are validated at build time before they are rendered into file names and the bind configuration.
- **Minimal non-root image:** the final image contains only `named` and its libraries (no shell, no interpreter, no package manager), built `FROM mwaeckerlin/scratch`, which runs as an unprivileged user.

Since the image is built from the rolling latest Alpine bind package, rebuild and redeploy regularly to pick up bind security fixes.

### Looking foreign names up: `RECURSION`

An authoritative server answers for its own zones. A resolver looks **any** name up: it asks the root servers, the responsible top level domain and the authoritative server, and returns what it gets. That is a useful service — a resolver of your own answers where a state-mandated filter in a provider's resolver does not — and it is off here unless you ask for it.

`RECURSION` names who may use it: an address, a network, a bind address list, or `any` for everybody. What it costs you:

- **Reflection and amplification.** An attacker sends a small query with a **forged sender address**, the one of his victim. Your server sends the much larger answer to that victim. Your machine and your line carry the traffic, and your address is what the victim sees. This is what `RATE_LIMIT` below is for; it limits the damage and cannot remove it, because the server must still answer legitimate queries. Setting `RECURSION` without `RATE_LIMIT` is the combination that gets a server abused.
- **Cache poisoning.** A resolver keeps a cache. An attacker who manages to have a forged answer accepted poisons that cache for everyone using the server. Current bind makes this hard (random source ports, random query identifiers, DNSSEC validation where the zone is signed), so it is an attack that needs luck and volume rather than a trick — but the class exists only once recursion is on. Without recursion there is no cache and nothing to poison.
- **Your resources.** Every foreign lookup is work and traffic you pay for.

The narrow setting is a network, not `any`: `RECURSION='10.0.0.0/8; 192.168.0.0/16'` serves your own clients and nobody else. `any` on a public address makes an open resolver; do that only deliberately, with `RATE_LIMIT` set.

### The limit on identical answers: `RATE_LIMIT`

`RATE_LIMIT` is the number of identical answers one client prefix gets per second (bind's response rate limiting). Above it, bind drops the answer or sends it truncated, which asks a genuine client to come back over TCP — where the sender address cannot be forged. It limits what your server contributes to an attack on somebody else, and it applies to an authoritative server too: reflection works with the zones you serve, recursion only makes the answers bigger.

Recommendation: `RATE_LIMIT='10'` for a public authoritative server; identical answers ten times per second per client prefix is far above what a real client asks for and far below what an attack needs. Set it lower only after watching the log. Unset there is no limit, which is the behaviour of every earlier version.

### Handing the zones to a secondary: `TRANSFER`

A zone transfer (`AXFR`) is how a secondary server takes over the zones of its master — the mechanism behind master and slave, and nothing is wrong with it. The question is who may ask. A single query has to know the name it asks for; a transfer returns the **complete** list: every zone, every subdomain, every address. That is the map an attacker otherwise has to guess, with the names of your administration, monitoring and test systems on it, so an open transfer is a finding in every security audit.

`TRANSFER` names the address of your secondary. Only that address may pull the zones, and it is notified when they change; everybody else is refused. Without the variable no transfer is allowed at all, which is right when every server of yours is built from the same image and none of them pulls.

Limitation: the permission is an address, and this image has no shared key (`TSIG`) for it. A key would have to be built into the image, and a secret in an image layer is what this image deliberately avoids. Where the transfer crosses a network you do not control, run it over a channel you do — or fetch the zones the way this image is configured in the first place, by building them in.
