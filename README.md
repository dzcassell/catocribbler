# catocribbler

Tenant-neutral reference implementation for integrating **Cato Networks EventsFeed** logs with **Cribl Stream**.

## Repository contents

- [`poller/poller.py`](poller/poller.py) — marker-aware EventsFeed poller
- [`poller/compose.yaml`](poller/compose.yaml) — container deployment with Docker secrets and persistent marker state
- [`poller/.env.example`](poller/.env.example) — sanitized tenant configuration template
- [`cribl/pipelines/cato_normalize/conf.yml`](cribl/pipelines/cato_normalize/conf.yml) — validated Cribl normalization Pipeline
- [`cribl/routes/cato_events_route.yml`](cribl/routes/cato_events_route.yml) — tenant-neutral Route example
- [`SECURITY.md`](SECURITY.md) — credential-handling guidance

## Quick start

1. Copy `poller/.env.example` to `poller/.env` and replace every placeholder.
2. Store the Cato API key in `poller/secrets/cato_api_key` and the Cribl CA certificate in `poller/secrets/cribl_ca.pem`.
3. Create a writable `poller/state/` directory owned by UID `10001`.
4. Deploy the Cribl Syslog Source, `cato_normalize` Pipeline, Route, and a validation Destination.
5. Start the poller with `docker compose up --build -d` from `poller/`.
6. Validate marker advancement, Cribl field promotion, and destination delivery before production cutover.

## What the poller does

- Authenticates to the customer-selected Cato API endpoint using a service API key read from a secret file.
- Retrieves EventsFeed pages using the persistent marker returned by Cato.
- Normalizes `fieldsMap` keys to snake case.
- Emits RFC 5424 syslog records to Cribl over TCP or TLS.
- Writes the next marker atomically only after the page is sent successfully.
- Immediately drains full 3,000-record pages before returning to the normal polling interval.

## Security

This repository intentionally contains no API keys, tenant account identifiers, private IP addresses, passwords, or customer-specific hostnames. Do not commit secrets or unsanitized event samples.

Store credentials in a vault, orchestrator secret, or protected local file with restrictive permissions. Rotate any credential that is exposed in source control, tickets, chat, or terminal transcripts.

## Support boundary

The poller is a tenant-neutral reference implementation and customer-managed code. Review, test, monitor, and maintain it under the customer's software-development and change-control standards.

Validate implementation details against current official Cato Networks and Cribl documentation before production deployment, since software products continue evolving despite everyone's objections.

## Disclaimer

This is an independent implementation guide and is not an official Cato Networks or Cribl publication. Product names and trademarks belong to their respective owners.
