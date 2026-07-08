# Cato EventsFeed to Cribl Stream

This repository contains a small Dockerized poller that retrieves security and network events from the **Cato Networks EventsFeed API** and forwards them to **Cribl Stream** as RFC 5424 syslog messages.

It is intended to be straightforward to deploy, tenant-neutral, and safe to operate with persistent marker state and secrets stored outside the container image.

## What the container does

The `cato-events-poller` container:

1. Reads a Cato API key from a Docker secret file.
2. Calls the Cato `eventsFeed` GraphQL API for one Cato account.
3. Uses Cato's opaque marker value to continue from the last successfully delivered page.
4. Promotes the Cato `fieldsMap` values into normalized snake-case JSON fields.
5. Wraps each JSON event in an RFC 5424 syslog record.
6. Sends the events to a Cribl Stream Syslog Source over TCP or TLS.
7. Advances the local marker only after the complete page has been sent successfully.
8. Immediately drains full 3,000-event pages before returning to the configured polling interval.

The normal data path is:

```text
Cato tenant
    |
    | HTTPS GraphQL EventsFeed
    v
cato-events-poller container
    |
    | RFC 5424 syslog over TCP or TLS
    v
Cribl Stream Syslog Source
    |
    v
Cribl Route -> cato_normalize Pipeline -> Destination
```

## Important behavior

- The poller handles one Cato account ID per container.
- The API key is not baked into the image and is not stored in `.env`.
- The Cato marker is persisted in `poller/state/marker.txt`.
- A missing or empty marker starts at the beginning of the events currently retained in the tenant's EventsFeed queue and can produce a large initial backlog.
- A page is acknowledged locally only after every event in that page has been sent to Cribl.
- `Fetched=N Sent=N` in the logs confirms that the complete page was emitted.
- `Fetched=0 Sent=0` is a successful poll with no new events.
- The container does not expose an inbound network port.

## Security characteristics

The supplied Compose deployment:

- Runs the poller as non-root UID `10001`.
- Uses a read-only container root filesystem.
- Uses a temporary in-memory `/tmp` filesystem.
- Applies `no-new-privileges`.
- Reads the API key and optional Cribl CA certificate as Docker secrets.
- Stores only the Cato marker in a writable bind-mounted directory.

Production deployments should use TLS between the poller and Cribl, restrict the Cato API key to the minimum required permissions, and protect the deployment directory as sensitive configuration.

## Repository contents

- [`poller/poller.py`](poller/poller.py): EventsFeed polling, normalization, marker handling, and syslog delivery.
- [`poller/Dockerfile`](poller/Dockerfile): Minimal Python image running as UID `10001`.
- [`poller/compose.yaml`](poller/compose.yaml): Hardened Docker Compose deployment.
- [`poller/.env.example`](poller/.env.example): Complete configuration template.
- [`cribl/pipelines/cato_normalize/conf.yml`](cribl/pipelines/cato_normalize/conf.yml): Cribl Pipeline that parses and promotes the JSON syslog payload.
- [`cribl/routes/cato_events_route.yml`](cribl/routes/cato_events_route.yml): Example Cribl Route for events emitted by this poller.
- [`docs/INSTALL.md`](docs/INSTALL.md): Complete installation and Cato configuration guide.
- [`docs/CRIBL.md`](docs/CRIBL.md): Cribl Source, Route, Pipeline, and Destination setup.
- [`docs/OPERATIONS.md`](docs/OPERATIONS.md): Verification, upgrades, backup, recovery, and troubleshooting.
- [`SECURITY.md`](SECURITY.md): Credential and deployment security guidance.

## Quick start

The detailed procedure is in [`docs/INSTALL.md`](docs/INSTALL.md). The abbreviated deployment is:

```bash
git clone https://github.com/dzcassell/catocribbler.git
cd catocribbler/poller

cp .env.example .env
mkdir -p secrets state

# Edit .env with the tenant's API URL, account ID, and Cribl listener.
nano .env

# Enter the API key without placing it in shell history.
umask 077
read -rsp "Cato API key: " CATO_KEY
printf '%s' "$CATO_KEY" > secrets/cato_api_key
unset CATO_KEY
printf '\n'

# TLS deployments: replace this with the CA chain that validates Cribl.
# Non-TLS lab deployments still need the declared file to exist.
: > secrets/cribl_ca.pem

# The container runs as UID 10001. It must be able to read the local
# secret source files and create/replace the persistent marker.
chown 10001 secrets/cato_api_key secrets/cribl_ca.pem state
chmod 0400 secrets/cato_api_key secrets/cribl_ca.pem
chmod 0700 state

# Validate, build, start, and follow the logs.
docker compose config
docker compose build --pull
docker compose up -d
docker compose logs -f cato-events-poller
```

A healthy cycle looks like:

```text
INFO starting marker_len=0
INFO Fetched=250 Sent=250 marker_len=180
```

The marker is opaque. Its length is shown only as an operational signal and is not guaranteed to remain 180 bytes.

## Required tenant information

Before deployment, obtain all of the following:

- A Cato API key authorized to call EventsFeed for the target tenant.
- The numeric Cato account ID.
- The correct regional Cato GraphQL API URL for that tenant.
- Confirmation that EventsFeed is enabled and receiving events.
- A reachable Cribl Stream Syslog Source hostname or IP address.
- The Cribl TCP port, normally `9514` in the supplied examples.
- For TLS, the server name on the Cribl certificate and the CA certificate chain that validates it.

Do not guess the Cato regional API hostname. Use the endpoint assigned to the tenant. For example, a US1 tenant may use:

```text
https://api.us1.catonetworks.com/api/v1/graphql2
```

Some Cato examples use the non-regional hostname:

```text
https://api.catonetworks.com/api/v1/graphql2
```

Use the exact endpoint appropriate for the tenant being polled.

## First-run warning

An empty marker can cause the poller to retrieve the full available EventsFeed backlog in consecutive pages of up to 3,000 events. Confirm that the Cribl Source and downstream Destination can absorb that volume before starting a new deployment.

When migrating an existing poller, copy the existing marker into `poller/state/marker.txt` before starting this container. Losing the marker can cause duplicate ingestion or a large replay.

## Support boundary

This is customer-managed reference code, not an official Cato Networks or Cribl product. Review, test, monitor, and maintain it under the customer's software-development, security, and change-control standards.

Product names and trademarks belong to their respective owners.
