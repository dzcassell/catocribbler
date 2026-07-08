# Cato EventsFeed to an existing Cribl Stream Docker deployment

This repository contains a small Dockerized poller that retrieves security and network events from the **Cato Networks EventsFeed API** and forwards them to an **existing Cribl Stream deployment running in Docker**.

## Project assumption

This project does **not** install, upgrade, replace, or manage Cribl Stream.

It assumes the customer already has:

- A working Cribl Stream single-instance or distributed Docker deployment.
- A Cribl Worker or single-instance container that can receive syslog.
- Administrative access to create or enable a Cribl Syslog Source, Route, Pipeline, and Destination.
- Docker access on the host running Cribl or on another host that can reach it.

The only new runtime component introduced by this repository is:

```text
cato-events-poller
```

## What the poller does

The container:

1. Reads a Cato API key from a protected Docker secret file.
2. Authenticates to the Cato GraphQL API using the `x-api-key` HTTP header.
3. Calls the Cato `eventsFeed` query for one numeric Cato account ID.
4. Uses Cato's opaque marker value to continue from the last successfully delivered page.
5. Promotes the Cato `fieldsMap` values into normalized snake-case JSON fields.
6. Wraps each JSON event in an RFC 5424 syslog record with `appname=cato-events`.
7. Sends the records to the customer's existing Cribl Syslog Source over TCP or TLS.
8. Advances the local marker only after the complete page has been written successfully to the Cribl socket.
9. Immediately drains full 3,000-record pages before returning to the configured polling interval.

The data path is:

```text
Cato tenant
    |
    | HTTPS GraphQL EventsFeed
    v
cato-events-poller container
    |
    | RFC 5424 syslog over TCP or TLS
    v
Existing Cribl Worker or single-instance container
    |
    v
Existing or new Cribl Syslog Source
    |
    v
cato_events_route -> cato_normalize -> customer Destination
```

## Docker connectivity to the existing Cribl container

Use one of these models.

### Published host port

The existing Cribl container publishes its Syslog TCP port to the Docker host, for example:

```text
0.0.0.0:9514->9514/tcp
```

Configure the poller to use the Docker host's LAN IP address or DNS name:

```dotenv
CRIBL_SYSLOG_HOST=192.0.2.25
CRIBL_SYSLOG_PORT=9514
```

Do not use `127.0.0.1` or `localhost`; inside the poller container those addresses refer to the poller itself.

### Shared external Docker network

Attach the poller to the existing Cribl Docker network and configure `CRIBL_SYSLOG_HOST` with the Cribl container or service name.

See [`docs/INSTALL.md`](docs/INSTALL.md) and [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) for the exact override file and discovery commands.

## Cato API-key choice

Cato provides two key types:

- **Admin API Key**: tied to an individual Cato administrator. Useful for personal testing.
- **Service API Key**: tied to a service principal and intended for shared automation and integrations. Recommended for a long-running production poller.

This integration performs read-only query operations. Use view-only permissions, the narrowest account scope available, source-IP restrictions where practical, and an expiration/rotation process.

Detailed creation and authentication tests are in:

- [`docs/INSTALL.md`](docs/INSTALL.md)
- [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md)

## Important behavior

- One poller container handles one Cato account ID.
- The API key is not baked into the image and is not stored in `.env`.
- The marker is persisted in `poller/state/marker.txt`.
- An empty marker starts at the beginning of the events currently retained in EventsFeed and can produce a large initial backlog.
- A page is acknowledged locally only after every event in the page has been written to Cribl's TCP socket.
- `Fetched=N Sent=N` confirms successful socket delivery of the complete page.
- `Fetched=0 Sent=0` is a successful poll with no new events.
- Matching `Fetched` and `Sent` counts do not by themselves prove that Cribl routing, parsing, or destination delivery succeeded. Validate those stages in Cribl.
- The poller exposes no inbound network port.

## Security characteristics

The supplied Compose deployment:

- Runs as non-root UID `10001`.
- Uses a read-only container root filesystem.
- Uses an in-memory `/tmp` filesystem.
- Applies `no-new-privileges`.
- Reads the Cato API key and optional Cribl CA chain as Docker secrets.
- Provides write access only to the persistent marker directory.

Use TLS between the poller and Cribl in production.

## Repository contents

- [`poller/poller.py`](poller/poller.py): EventsFeed polling, normalization, marker handling, and syslog delivery.
- [`poller/Dockerfile`](poller/Dockerfile): Minimal Python image running as UID `10001`.
- [`poller/compose.yaml`](poller/compose.yaml): Hardened standalone poller deployment.
- [`poller/.env.example`](poller/.env.example): Complete configuration template.
- [`cribl/pipelines/cato_normalize/conf.yml`](cribl/pipelines/cato_normalize/conf.yml): Cribl normalization Pipeline.
- [`cribl/routes/cato_events_route.yml`](cribl/routes/cato_events_route.yml): Route compatible with any existing Cribl Syslog Source ID when `appname=cato-events`.
- [`docs/INSTALL.md`](docs/INSTALL.md): Installation into an environment with Cribl already running in Docker.
- [`docs/CRIBL.md`](docs/CRIBL.md): Integrating the poller with the existing Cribl container and configuration.
- [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md): End-to-end Cato authentication, Docker networking, Cribl, TLS, routing, and permission troubleshooting.
- [`docs/OPERATIONS.md`](docs/OPERATIONS.md): Upgrades, backup, recovery, rotation, and monitoring.
- [`SECURITY.md`](SECURITY.md): Credential and deployment security guidance.

## Required information

Collect these values before deployment:

### Cato

- Correct regional GraphQL API URL.
- Numeric Cato account ID.
- Admin API Key for testing or Service API Key for production.
- Confirmation that EventsFeed is available for the account.
- Public egress IP of the Docker host if the key uses source-IP restrictions.

### Existing Cribl deployment

- Name of the Cribl Worker or single-instance container.
- Docker network name or published Syslog host port.
- Syslog TCP port, commonly `9514`.
- Existing Source ID, or permission to create/enable a Syslog Source.
- Worker Group receiving the Source configuration.
- Destination ID for validation or production.
- TLS server name and CA chain when TLS is enabled.

## Quick start

Read the full installation guide before production deployment. The abbreviated flow is:

```bash
git clone https://github.com/dzcassell/catocribbler.git
cd catocribbler/poller

cp .env.example .env
mkdir -p secrets state
nano .env

umask 077
read -rsp "Cato API key: " CATO_KEY
printf '%s' "$CATO_KEY" > secrets/cato_api_key
unset CATO_KEY
printf '\n'

# Replace with the CA chain for a TLS Cribl Source.
# Keep an empty placeholder only for a non-TLS lab listener.
: > secrets/cribl_ca.pem

chown 10001 secrets/cato_api_key secrets/cribl_ca.pem state
chmod 0400 secrets/cato_api_key secrets/cribl_ca.pem
chmod 0700 state

docker compose config
docker compose build --pull

# Test Cato before starting continuous polling.
# See docs/INSTALL.md for the complete non-destructive preflight.

docker compose up -d
docker compose logs -f cato-events-poller
```

Healthy polling looks like:

```text
INFO starting marker_len=0
INFO Fetched=250 Sent=250 marker_len=180
```

The marker is opaque. Its length is not guaranteed to remain 180 bytes.

## First-run warning

An empty marker can retrieve the full available EventsFeed backlog in consecutive pages of up to 3,000 events. Confirm that the existing Cribl Source, routing, queues, and downstream Destination can absorb that volume before starting.

When replacing another poller, preserve its current marker and place it in `poller/state/marker.txt` before cutover.

## Troubleshooting entry point

Start with [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md). It deliberately separates:

1. Cato key creation and API authentication.
2. Docker connectivity to the existing Cribl container.
3. Cribl Source, Route, Pipeline, and Destination validation.
4. Poller permissions and marker state.

## Support boundary

This is customer-managed reference code, not an official Cato Networks or Cribl product. Review, test, monitor, and maintain it under the customer's software-development, security, and change-control standards.

Product names and trademarks belong to their respective owners.
