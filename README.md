# Cato EventsFeed to an existing Cribl Stream Docker deployment

> [!CAUTION]
> **UNSUPPORTED, NON-PRODUCTION DEMONSTRATION CODE.** This repository is not supported by Damon Cassell, the repository owner, Cato Networks, Cribl, any employer, contributor, vendor, partner, or anyone else. It is not an official or approved integration. There is no support commitment, no maintenance commitment, no warranty, and no license grant from the author. Do not use it in production. Read [`DISCLAIMER.md`](DISCLAIMER.md).

This repository contains experimental demonstration code showing one possible way to retrieve events from the **Cato Networks EventsFeed API** and forward them to an **existing Cribl Stream deployment running in Docker**.

Its presence on GitHub does not make it production-ready, supported, endorsed, licensed, safe, complete, or suitable for any purpose. Apparently repositories do not arrive with warning sirens, so this paragraph must perform the task.

## Interactive installer

The repository includes an interactive [`install.sh`](install.sh) wrapper.

Current defaults:

| Setting | Default |
|---|---|
| Installation directory | `/opt/cribbler` |
| Cato GraphQL API URL | `https://api.catonetworks.com/api/v1/graphql` |
| Cribl connection method | Published host TCP port |
| Cribl Syslog TCP port | `9514` |
| Cribl TLS | Disabled |
| Poll interval | 30 seconds |

Recommended pinned installation:

```bash
INSTALL_REF=<reviewed-commit-sha>

curl -fsSLo /tmp/catocribbler-install.sh \
  "https://raw.githubusercontent.com/dzcassell/catocribbler/${INSTALL_REF}/install.sh"

less /tmp/catocribbler-install.sh

sudo env \
  CATOCRIBBLER_REF="${INSTALL_REF}" \
  bash /tmp/catocribbler-install.sh
```

The installer reads answers from `/dev/tty`, so prompts remain interactive when Bash receives the script through a pipe. It builds the image, runs independent Cato and Cribl preflights, can send one synthetic event, and leaves continuous polling stopped unless the evaluator explicitly types `START` after the backlog warning.

See [`docs/INSTALLER.md`](docs/INSTALLER.md) and [`docs/INSTALL.md`](docs/INSTALL.md).

## Project assumption

This project does **not** install, upgrade, replace, or manage Cribl Stream.

It assumes an evaluator already has:

- A non-production Cribl Stream single-instance or distributed Docker deployment.
- A Cribl Worker or single-instance container that can receive test syslog data.
- Administrative access to create or enable a Cribl Syslog Source, Route, Pipeline, and test Destination.
- Docker access on the host running Cribl or on another isolated host that can reach it.
- Permission to perform a non-production demonstration using synthetic or specifically approved test data.

The only new runtime component introduced is:

```text
cato-events-poller
```

## What the poller does

The container:

1. Reads a Cato API key from a protected Docker secret file.
2. Authenticates to the Cato GraphQL API using `x-api-key`.
3. Calls `eventsFeed` for one numeric Cato account ID.
4. Uses Cato's opaque marker to continue from the last successfully delivered page.
5. Promotes Cato `fieldsMap` values into normalized snake-case JSON fields.
6. Wraps each JSON event in RFC 5424 syslog with `appname=cato-events`.
7. Sends records to an existing Cribl Syslog Source over TCP or TLS.
8. Advances the local marker only after the complete page has been written to the Cribl socket.
9. Immediately drains full 3,000-record pages before returning to the configured polling interval.

## Cribl connection methods

### Published host TCP port, recommended default

Use this when the Cribl container publishes the Syslog Source port to the Docker host:

```text
0.0.0.0:9514->9514/tcp
```

Configure the poller with the Docker host's LAN IP address or DNS name.

This is the recommended default because it:

- Is simpler to explain and troubleshoot.
- Does not attach the poller to Cribl's internal Docker network.
- Does not depend on local Docker network names and aliases.
- Is more portable between customer environments.

Do not use `localhost` or `127.0.0.1`; inside the poller container those addresses refer to the poller itself.

### Shared external Docker network, advanced fallback

Use this only when the Syslog TCP port is not published or direct container-to-container connectivity is specifically required.

The poller joins an existing non-production Cribl Docker network and connects using the Cribl container, service, or network-alias name.

This method is less portable and gives the poller access to other services exposed on that network.

**Recommendation:** choose the published host TCP port unless the listener is not published or the deployment specifically requires a shared Docker network.

## Cato API-key choice

Cato provides:

- **Admin API Key**, tied to an individual administrator.
- **Service API Key**, tied to a service principal.

For a shared demonstration, a dedicated Service API Key with Viewer permissions, narrow scope, source-IP restrictions, short expiration, and prompt revocation is preferable.

Neither choice makes this code appropriate for production.

## Important limitations

- One poller container handles one Cato account ID.
- The API key is not baked into the image and is not stored in `.env`.
- The marker is persisted in `poller/state/marker.txt`.
- An empty marker can retrieve the beginning of retained EventsFeed data and create a large replay.
- A page is acknowledged locally only after every event has been written to Cribl's TCP socket.
- `Fetched=N Sent=N` confirms socket writes, not downstream Cribl persistence.
- `Fetched=0 Sent=0` is a successful poll with no new events.
- The poller exposes no inbound network port.
- The code has not been tested for production scale, failure recovery, long-term compatibility, security, privacy, regulatory compliance, or operational readiness.
- It can lose, duplicate, delay, reorder, expose, or replay events.

## Security characteristics are not a certification

The supplied Compose deployment:

- Runs as non-root UID `10001`.
- Uses a read-only container root filesystem.
- Uses an in-memory `/tmp` filesystem.
- Applies `no-new-privileges`.
- Reads the Cato API key and optional Cribl CA chain as Docker secrets.
- Provides write access only to persistent marker state.

These are demonstration safeguards, not proof of security, correctness, suitability, or production readiness.

## Repository contents

- [`DISCLAIMER.md`](DISCLAIMER.md): unsupported-code, no-license, no-warranty, and liability notice.
- [`install.sh`](install.sh): guided interactive installer.
- [`poller/poller.py`](poller/poller.py): EventsFeed polling, normalization, marker handling, and syslog delivery.
- [`poller/Dockerfile`](poller/Dockerfile): Python image running as UID `10001`.
- [`poller/compose.yaml`](poller/compose.yaml): standalone poller deployment.
- [`poller/.env.example`](poller/.env.example): configuration template.
- [`cribl/pipelines/cato_normalize/conf.yml`](cribl/pipelines/cato_normalize/conf.yml): demonstration normalization Pipeline.
- [`cribl/routes/cato_events_route.yml`](cribl/routes/cato_events_route.yml): demonstration Route.
- [`docs/INSTALLER.md`](docs/INSTALLER.md): installer behavior and prompts.
- [`docs/INSTALL.md`](docs/INSTALL.md): fresh-install sequence.
- [`docs/CRIBL.md`](docs/CRIBL.md): Cribl integration.
- [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md): diagnostics.
- [`docs/OPERATIONS.md`](docs/OPERATIONS.md): lifecycle and cleanup.
- [`SECURITY.md`](SECURITY.md): security cautions.

## First-run danger

A new installation has no marker. Starting continuous polling can retrieve all events currently retained by EventsFeed in consecutive pages of up to 3,000 records. This can create duplicates, unexpected volume, licensing impact, storage consumption, or downstream cost.

Do not point the demonstration at production data, production Cribl, or a production Destination.

## No support, no license, no warranty

This repository is not supported by Damon Cassell, Cato Networks, Cribl, any employer, contributor, vendor, partner, customer, or other party.

It intentionally contains no `LICENSE` file and grants no license from the author. It is provided “AS IS” and “AS AVAILABLE,” with no warranties and no liability to the maximum extent permitted by applicable law.
