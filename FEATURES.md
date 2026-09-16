# Features

Numbered register of everything this image does for the administrator who operates it and for the client that queries it; a number is never reused. Every feature is covered by tests listed in [TESTS.md](TESTS.md); the guard `tests/docs-contract.sh` fails when a feature has no test.

- **F1 Zone per domain** — every name in `DOMAINS` and `DEFAULT_DOMAINS` gets its own master zone with `SOA`, `NS` and an `A` record on its address; the address comes from the domain entry or from `DEFAULT_IP`.
- **F2 Default subdomains** — a domain without its own subdomain list gets the names in `DEFAULT_SUBDOMAINS` as `CNAME` on the domain; without that variable the wildcard answers for every name under the domain.
- **F3 Subdomain with its own record** — a subdomain written as `name=TYPE:value` becomes that record (`A`, `AAAA`, `CNAME`, …) on that value instead of a `CNAME` on the domain.
- **F4 Free-form records** — everything after the second semicolon of a domain entry is written into the zone unchanged, so `TXT`, `SRV` and further `MX` records are possible; `\t` becomes a tabulator.
- **F5 Mail server** — every zone gets `MX 10` on the name in `MAILSERVER`; without that variable the domain itself is the mail server.
- **F6 Zone timing** — `TTL`, `SERIAL`, `REFRESH`, `RETRY`, `EXPIRE` and `NEGATIVE_CACHE_TTL` set the values of the `SOA` record; the serial defaults to the build time.
- **F7 Transfer to a secondary** — with `TRANSFER` set, the named address may pull the zones and is notified on change; without it no transfer is allowed.
- **F8 Authoritative-only server** — recursion, zone transfer, version disclosure and the remote control channel are refused, and the generated control key is removed, so no secret lies in an image layer.
- **F9 Validated domain names** — a name with characters outside letters, digits, dot and hyphen stops the build before it reaches a file name or the configuration.
- **F10 Minimal image** — the delivered image contains `named` and its libraries only, without a shell, without an interpreter and without a package manager, and it runs as an unprivileged user.
- **F11 Configuration at build time** — the whole configuration is generated during the build, from `domains.sh` or from build arguments, and the finished configuration is checked with `named-checkconf` before the image is written. A build argument wins over the file, so `domains.sh` carries the configuration of the project and the argument the exception of one build.
- **F12 Port 9953 over both transports** — the service listens on 9953 for UDP and for TCP, so it runs beside a `named` of the host and an answer too large for one datagram is fetched over TCP.
- **F13 Log level** — the server logs to standard output, where `docker logs` shows it; `SEVERITY` decides how much, from `debug` to `critical`, and at the default `warning` a single query is not logged.
- **F14 Configuration at run time** — a volume mounted on `/etc/bind` replaces the configuration that was built into the image completely, so the same image serves an arbitrary configuration without a build.
