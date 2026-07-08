# Cato EventsFeed to an existing Cribl Stream Docker deployment

> [!CAUTION]
> **UNSUPPORTED, NON-PRODUCTION DEMONSTRATION CODE.** This repository is not supported by Damon Cassell, the repository owner, Cato Networks, Cribl, any employer, contributor, vendor, partner, or anyone else. It is not an official or approved integration. There is no support commitment, no maintenance commitment, no warranty, and no license grant from the author. Do not use it in production. Read [`DISCLAIMER.md`](DISCLAIMER.md) before viewing, evaluating, or attempting to use the material.

This repository contains experimental demonstration code showing one possible way to retrieve security and network events from the **Cato Networks EventsFeed API** and forward them to an **existing Cribl Stream deployment running in Docker**.

Its presence on GitHub does not make it production-ready, supported, endorsed, licensed, safe, complete, or suitable for any purpose. Apparently repositories do not arrive with warning sirens, so this paragraph must perform the task.

## Project assumption

This project does **not** install, upgrade, replace, or manage Cribl Stream.

It assumes an evaluator already has:

- A non-production Cribl Stream single-instance or distributed Docker deployment.
- A Cribl Worker or single-instance container that can receive test syslog data.
- Administrative access to create or enable a Cribl Syslog Source, Route, Pipeline, and test Destination.
- Docker access on the host running Cribl or on another isolated host that can reach it.
- Permission to perform a non-production demonstration using synthetic or specifically approved test data.

The only new runtime component introduced by this repository is:

```text
cato-events-poller
```

## What the demonstration poller does

The container:

1. Reads a Cato API key from a protected Docker secret file.
2. Authenticates to the Cato GraphQL API using the `x-api-key` HTTP header.
3. Calls the Cato `eventsFeed` query for one numeric Cato account ID.
4. Uses Cato's opaque marker value to continue from the last successfully delivered page.
5. Promotes Cato `fieldsMap` values into normalized snake-case JSON fields.
6. Wraps each JSON event in an RFC 5424 syslog record with `appname=cato-events`.
7. Sends the records to an existing Cribl Syslog Source over TCP or TLS.
8. Advances the local marker only after the complete page has been written successfully to the Cribl socket.
9. Immediately drains full 3,000-record pages before returning to the configured polling interval.

The demonstration data path is:

```text
Non-production Cato test tenant or specifically approved test account
    |
    | HTTPS GraphQL EventsFeed
    v
cato-events-poller demonstration container
    |
    | RFC 5424 syslog over TCP or TLS
    v
Existing non-production Cribl Worker or single-instance container
    |
    v
Existing or new Cribl Syslog Source
    |
    v
cato_events_route -> cato_normalize -> isolated test Destination
```

## Docker connectivity to the existing Cribl container

Use one of these evaluation models.

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

Attaching the poller to an existing Docker network expands its network reach. Review that change independently and use an isolated test environment.

## Cato API-key choice for evaluation

Cato provides two key types:

- **Admin API Key**: tied to an individual Cato administrator. It can be used for a controlled personal test.
- **Service API Key**: tied to a service principal. It may be operationally preferable for a shared demonstration because it is not tied to a human administrator.

Neither choice makes this code appropriate for production.

This demonstration performs read-only query operations. Use view-only permissions, the narrowest account scope available, source-IP restrictions where practical, a short expiration, and prompt revocation when testing ends.

Detailed creation and authentication tests are in:

- [`docs/INSTALL.md`](docs/INSTALL.md)
- [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md)

## Important limitations

- One poller container handles one Cato account ID.
- The API key is not baked into the image and is not stored in `.env`.
- The marker is persisted in `poller/state/marker.txt`.
- An empty marker can retrieve the beginning of the events currently retained in EventsFeed and can create a large replay.
- A page is acknowledged locally only after every event in the page has been written to Cribl's TCP socket.
- `Fetched=N Sent=N` confirms successful socket writes for the complete page.
- `Fetched=0 Sent=0` is a successful poll with no new events.
- Matching `Fetched` and `Sent` counts do not prove that Cribl routing, parsing, persistence, or destination delivery succeeded.
- The poller exposes no inbound network port.
- The code has not been tested for production scale, failure recovery, long-term compatibility, security, privacy, regulatory compliance, or operational readiness.
- It can lose, duplicate, delay, reorder, expose, or replay events.

## Security characteristics are not a production certification

The supplied Compose deployment:

- Runs as non-root UID `10001`.
- Uses a read-only container root filesystem.
- Uses an in-memory `/tmp` filesystem.
- Applies `no-new-privileges`.
- Reads the Cato API key and optional Cribl CA chain as Docker secrets.
- Provides write access only to the persistent marker directory.

These controls are demonstration safeguards, not proof of security, correctness, suitability, or production readiness.

## Repository contents

- [`DISCLAIMER.md`](DISCLAIMER.md): full unsupported-code, no-license, no-warranty, and limitation-of-liability notice.
- [`poller/poller.py`](poller/poller.py): experimental EventsFeed polling, normalization, marker handling, and syslog delivery.
- [`poller/Dockerfile`](poller/Dockerfile): demonstration Python image running as UID `10001`.
- [`poller/compose.yaml`](poller/compose.yaml): standalone demonstration poller deployment.
- [`poller/.env.example`](poller/.env.example): configuration template for an isolated evaluation.
- [`cribl/pipelines/cato_normalize/conf.yml`](cribl/pipelines/cato_normalize/conf.yml): demonstration Cribl normalization Pipeline.
- [`cribl/routes/cato_events_route.yml`](cribl/routes/cato_events_route.yml): demonstration Route compatible with any Syslog Source ID when `appname=cato-events`.
- [`docs/INSTALL.md`](docs/INSTALL.md): non-production installation beside an existing Cribl Docker environment.
- [`docs/CRIBL.md`](docs/CRIBL.md): demonstration integration with the existing Cribl container and configuration.
- [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md): Cato authentication, Docker networking, Cribl, TLS, routing, and permissions troubleshooting.
- [`docs/OPERATIONS.md`](docs/OPERATIONS.md): limited demonstration lifecycle, backup, cleanup, and monitoring guidance.
- [`SECURITY.md`](SECURITY.md): security cautions for evaluating the demonstration.

## Required information for a controlled demonstration

Collect these values before testing:

### Cato

- Correct regional GraphQL API URL.
- Numeric Cato account ID for a test tenant or specifically approved test account.
- Short-lived Admin API Key or Service API Key restricted for the demonstration.
- Confirmation that EventsFeed is available for the approved test account.
- Public egress IP of the Docker host if source-IP restrictions are used.

### Existing non-production Cribl environment

- Name of the Cribl Worker or single-instance container.
- Docker network name or published Syslog host port.
- Syslog TCP port, commonly `9514`.
- Existing Source ID, or permission to create or enable a test Syslog Source.
- Worker Group receiving the test configuration.
- Isolated test Destination ID.
- TLS server name and CA chain when TLS is enabled.

## Abbreviated demonstration setup

Read [`DISCLAIMER.md`](DISCLAIMER.md) and the full installation guide before doing anything. Use only an isolated, disposable, non-production environment.

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

# Replace with the CA chain for a TLS test Source.
# Keep an empty placeholder only for an isolated non-TLS lab listener.
: > secrets/cribl_ca.pem

chown 10001 secrets/cato_api_key secrets/cribl_ca.pem state
chmod 0400 secrets/cato_api_key secrets/cribl_ca.pem
chmod 0700 state

docker compose config
docker compose build --pull

# Run the documented non-destructive preflights before continuous polling.

docker compose up -d
docker compose logs -f cato-events-poller
```

A successful demonstration cycle may look like:

```text
INFO starting marker_len=0
INFO Fetched=250 Sent=250 marker_len=180
```

The marker is opaque. Its length is not guaranteed to remain 180 bytes.

## First-run danger

An empty marker can retrieve the full available EventsFeed backlog in consecutive pages of up to 3,000 events. This can create duplicates, unexpected volume, licensing impact, storage consumption, or downstream cost.

Do not point the demonstration at production data, production Cribl, or a production Destination.

## Troubleshooting entry point

Start with [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md). It separates:

1. Cato key creation and API authentication.
2. Docker connectivity to the existing Cribl test container.
3. Cribl Source, Route, Pipeline, and test Destination validation.
4. Poller permissions and marker state.

## No support, no license, no warranty

This repository is not supported by Damon Cassell, Cato Networks, Cribl, any employer, contributor, vendor, partner, customer, or other party.

It intentionally contains no `LICENSE` file and grants no license from the author. It is provided “AS IS” and “AS AVAILABLE,” with no warranties or conditions and no liability to the maximum extent permitted by applicable law.

Read the complete [`DISCLAIMER.md`](DISCLAIMER.md). Product names and trademarks belong to their respective owners.
