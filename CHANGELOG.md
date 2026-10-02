# Changelog

- 2026-10-02 **1.0.1**
    - The image is published for amd64 and arm64 under one tag, built and published automatically on every change and every week
    - The server looks foreign names up where `RECURSION` names who may ask — an address, a network or `any` for everybody; without the variable it answers for its own zones only, as before. The README names what comes with it: reflection with a forged sender address, cache poisoning, and your own traffic
    - `RATE_LIMIT` limits how many identical answers one client prefix gets per second, which is what caps the server's contribution to an attack on somebody else; recommended `10` on a public server, unset there is no limit
    - `TRANSFER`, the permission for a secondary server to pull the zones, is documented with what an open transfer gives away — the complete list of every zone, subdomain and address — and with the limit that the permission is an address and not a shared key

- 2026-09-16 **1.0.0**
    - The server answers for its own zones only: recursion is switched off, so the image can no longer be used as an open resolver or to amplify an attack
    - Zone transfers are refused unless a secondary server is named in `TRANSFER`, so the complete list of domains and hosts cannot be fetched
    - The bind version is no longer disclosed, and the remote control channel is switched off
    - The control key the build generates is deleted instead of shipped — it no longer lies in a layer of the published image
    - The mail server of the `MX` record is configurable again: `MAILSERVER` now reaches the configuration, so all domains can deliver their mail to one host instead of to themselves
    - The image builds again with the current base image, where the ownership of the configuration directories was set in a form that is no longer accepted
    - A domain name that is not a domain name stops the build before it reaches a file name or the server configuration
    - The service answers over TCP as well, which a large answer and a zone transfer need
    - `npm test` runs the whole suite: what the image contains, what its configuration says, and four servers asked record by record — the configuration of this repository, the defaults, every variable with a value of its own, and a configuration mounted at run time; `./test.sh <server>` asks a deployed server the same questions
    - The log level `SEVERITY` is documented, and what the image does is written down in `FEATURES.md`, which test covers it in `TESTS.md`
