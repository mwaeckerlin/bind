# Tests

Register of all tests, grouped by kind and sorted by the [FEATURES.md](FEATURES.md) number each test covers. `npm test` runs everything; the guard `tests/docs-contract.sh` fails when a feature has no test entry here or when any test carries a skip/xfail marker — tests are never skipped.

The configuration under test is never written down twice: `tests/run-e2e.sh` reads the build arguments out of `docker-compose.yaml` and hands them to the stack, so the `production` service serves exactly the domains the tests ask for.

The e2e stack (`tests/e2e/`) holds one server per usage: `production` with the configuration of this repository, `defaults` with nothing but the domains and one address, `configured` with every build argument set to a value of its own, and `mounted` with an `/etc/bind` that was never built into the image.

## E2E — DNS (pytest against the real compose stack)

- **F1** `tests/e2e/test_records.py` › test_domain_address — every configured domain answers with the address of its entry, or with `DEFAULT_IP` where the entry names none.
- **F1** `tests/e2e/test_records.py` › test_domain_name_server — every domain is its own name server.
- **F1** `tests/e2e/test_records.py` › test_domain_start_of_authority — the `SOA` record carries the zone, the mailbox and the configured times.
- **F1** `tests/e2e/test_defaults.py` › test_a_domain_from_the_default_list, test_a_domain_that_names_no_address, test_a_domain_that_names_its_address — `DEFAULT_DOMAINS`, a bare name in `DOMAINS` and a name with its own address.
- **F1** `tests/e2e/test_configured.py` › test_default_address, test_domain_with_its_own_address, test_domain_that_names_nothing_but_its_address, test_domain_from_the_default_list.
- **F2** `tests/e2e/test_records.py` › test_subdomains — every default subdomain is a `CNAME` on its domain and resolves to that domain's address.
- **F2** `tests/e2e/test_defaults.py` › test_without_a_subdomain_list_every_name_answers — without `DEFAULT_SUBDOMAINS` the wildcard answers for any name.
- **F2** `tests/e2e/test_configured.py` › test_default_subdomains, test_own_subdomain_list_replaces_the_default_one — a domain with its own list does not get the default one.
- **F3** `tests/e2e/test_records.py` › test_subdomains — a subdomain written as `name=TYPE:value` carries that record and no `CNAME`.
- **F3** `tests/e2e/test_configured.py` › test_subdomain_on_its_own_address, test_subdomain_with_an_address_of_the_sixth_version, test_subdomain_that_points_at_another_domain — `A`, `AAAA` and `CNAME` on a subdomain.
- **F4** `tests/e2e/test_records.py` › test_free_form_records — every free form record of every domain is read out of the configuration and asked for.
- **F4** `tests/e2e/test_configured.py` › test_free_form_text_record, test_free_form_mail_record — a `TXT` and an additional `MX` record with their tabulators.
- **F5** `tests/e2e/test_records.py` › test_domain_mail_server — every domain answers `MX 10` with the name in `MAILSERVER`.
- **F5** `tests/e2e/test_defaults.py` › test_without_a_mail_server_the_domain_is_its_own — without the variable the domain itself is the mail server.
- **F5** `tests/e2e/test_configured.py` › test_mail_server_of_every_domain.
- **F6** `tests/e2e/test_records.py` › test_domain_time_to_live, test_domain_start_of_authority — time to live, serial, refresh, retry, expire and negative cache time.
- **F6** `tests/e2e/test_defaults.py` › test_default_time_to_live, test_default_times_of_the_zone, test_the_serial_is_the_build_time — the documented defaults.
- **F6** `tests/e2e/test_configured.py` › test_serial_number, test_times_of_the_zone, test_time_to_live — each value set to one of its own.
- **F7** `tests/e2e/test_transfer.py` › test_the_secondary_receives_the_whole_zone — from the address in `TRANSFER` the whole zone arrives, record by record.
- **F7** `tests/e2e/test_transfer.py` › test_every_configured_zone_can_be_pulled, test_a_zone_that_does_not_exist_is_not_transferred.
- **F7** `tests/e2e/test_hardening.py` › test_the_zone_transfer_is_refused — without `TRANSFER` the same request is refused.
- **F8** `tests/e2e/test_hardening.py` › test_recursion_is_refused, test_a_foreign_zone_is_not_answered, test_the_version_is_not_disclosed.
- **F12** `tests/e2e/test_transport.py` › test_the_same_answer_over_both_transports — the same query over UDP and over TCP.
- **F13** `tests/run-e2e.sh` › log level — the `production` server at the default level writes no line per query, the `configured` server with `SEVERITY=info` writes one.
- **F14** `tests/e2e/test_mounted.py` › test_the_mounted_zone_answers, test_its_subdomain_answers, test_its_mail_server_answers, test_the_zone_built_into_the_image_is_gone — the mounted configuration replaces the built one completely.

## Config contract (`tests/config-contract.sh`)

Reads the configuration out of the shipped image and builds the cases that must not become an image.

- **F8** `tests/config-contract.sh` › recursion_off, no_transfer, version_hidden, no_control_channel — the four hardening settings stand in the configuration the image ships.
- **F1** `tests/config-contract.sh` › zones_configured, master_zones — the image carries master zones.
- **F9** `tests/config-contract.sh` › refuses_a_path, refuses_a_name_with_a_space, refuses_a_name_with_a_quote, refuses_a_name_with_two_dots — each build ends with «invalid domain name», while accepts_an_ordinary_name builds.
- **F11** `tests/config-contract.sh` › address_from_domains_sh, mailserver_from_domains_sh, subdomains_from_domains_sh — the configuration is taken from `domains.sh` as well; the build arguments are what every service of the e2e stack is built with.
- **F12** `tests/config-contract.sh` › service_port — the server listens on port 9953.

## Image contract (`tests/image-contract.sh`)

- **F10** `tests/image-contract.sh` › no_sh, no_bash, no_busybox, no_perl, no_package_manager, unprivileged_user — no shell, no interpreter, no package manager, and the image runs as `somebody`.
- **F8** `tests/image-contract.sh` › no_control_key — the generated `rndc.key` is not in the image.
- **F11** `tests/image-contract.sh` › holds_the_server, holds_the_configuration — `named` and the generated `named.conf` are in the image.
- **F12** `tests/image-contract.sh` › service_ports — 9953 is exposed for UDP and for TCP.

## Docs contract (`tests/docs-contract.sh`)

- **F1**–**F14** every feature of `FEATURES.md` carries an entry here, every number used here exists as a feature, no number is defined twice and no test is skipped.
