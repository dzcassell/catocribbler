# Cato EventsFeed to an existing Cribl Stream Docker deployment

> [!CAUTION]
> **UNSUPPORTED, NON-PRODUCTION DEMONSTRATION CODE.** This repository is not supported by Damon Cassell, Cato Networks, Cribl, any employer, contributor, vendor, partner, or anyone else. It is not an official integration. There is no support commitment, maintenance commitment, warranty, or license grant. Do not use it in production. Read [`DISCLAIMER.md`](DISCLAIMER.md).

This repository demonstrates one possible way to retrieve events from the Cato Networks EventsFeed API and forward them to an existing Cribl Stream deployment running in Docker.

## Customer installation

Run this command from an interactive Linux terminal on the Docker host:

```bash
curl -fsSL https://raw.githubusercontent.com/dzcassell/catocribbler/main/install.sh | sudo bash
```

That is the complete launch command. The installer handles the remaining questions interactively.

The installer will:

- Default to `/opt/cribbler` and create the directory when needed.
- Default to `https://api.catonetworks.com/api/v1/graphql`.
- Ask for the numeric Cato account ID.
- Detect a running Cribl container publishing `9514/tcp`.
- Detect the Docker host address and suggest the working Cribl endpoint.
- Ask for the Cato API key without displaying it.
- Build the poller container.
- Test Cato authentication.
- Test the connection to Cribl.
- Offer to send one synthetic test event.
- Require the operator to type `START` before continuous polling begins.

For a normal installation, most prompts can be accepted by pressing Enter.

## Example Cribl detection

```text
The installer found a running Cribl container with a published Syslog listener:

  Cribl container:            cribl-worker
  Docker port mapping:        0.0.0.0:9514
  Address the poller will use: 192.168.40.15:9514

Use this detected Cribl listener [Y/n]:
```

Press Enter when the detected container and address are correct. The installer asks for manual networking information only when automatic detection fails or the detected listener is rejected.

## Information to have ready

Before starting, collect:

### Cato

- Numeric Cato account ID
- Fresh Service API Key with read-only permissions
- Approval to use EventsFeed for the demonstration

### Cribl

- A running non-production Cribl Worker or single-instance container
- An enabled TCP Syslog Source, normally on port `9514`
- A test Route, Pipeline, and isolated Destination

## Defaults

| Setting | Default |
|---|---|
| Installation directory | `/opt/cribbler` |
| Cato GraphQL API URL | `https://api.catonetworks.com/api/v1/graphql` |
| Cribl connection | Automatically detected published TCP listener |
| Cribl Syslog port | `9514` |
| Cribl TLS | Disabled |
| Poll interval | 30 seconds |

## What the poller does

The `cato-events-poller` container:

1. Reads the Cato API key from a protected secret file.
2. Calls the Cato EventsFeed GraphQL query.
3. Uses Cato's opaque marker to continue from the last successfully delivered page.
4. Normalizes Cato `fieldsMap` values into JSON fields.
5. Wraps each event in RFC 5424 syslog with `appname=cato-events`.
6. Sends records to the existing Cribl Syslog Source over TCP or TLS.
7. Advances the marker only after the complete page has been written to the Cribl socket.

## First-run warning

A new installation has no EventsFeed marker. Starting continuous polling can retrieve all events currently retained by EventsFeed in consecutive pages of up to 3,000 records.

The installer therefore performs authentication and connectivity tests first and will not start continuous polling until the operator types:

```text
START
```

## After installation

```bash
cd /opt/cribbler/poller

docker compose ps
docker compose logs -f cato-events-poller
docker compose stop cato-events-poller
docker compose up -d
docker compose down
```

The API key is stored in:

```text
/opt/cribbler/poller/secrets/cato_api_key
```

The installer records non-secret installation details, including the exact installed Git commit, in:

```text
/opt/cribbler/INSTALLATION_INFO.txt
```

The customer does not need to select or enter a commit identifier.

## Important limitations

- One poller container handles one Cato account ID.
- An empty marker can create a large replay.
- `Fetched=N Sent=N` confirms socket writes, not downstream Cribl persistence.
- The code has not been tested for production scale, long-term compatibility, regulatory compliance, or operational readiness.
- It can lose, duplicate, delay, reorder, expose, or replay events.

## Documentation

- [`docs/INSTALLER.md`](docs/INSTALLER.md): installer prompts and behavior
- [`docs/INSTALL.md`](docs/INSTALL.md): fresh customer installation sequence
- [`docs/CRIBL.md`](docs/CRIBL.md): Cribl configuration guidance
- [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md): diagnostics
- [`docs/OPERATIONS.md`](docs/OPERATIONS.md): lifecycle and cleanup
- [`SECURITY.md`](SECURITY.md): security cautions

## No support, no license, no warranty

This repository is provided “AS IS” and “AS AVAILABLE.” It contains no license grant from the author and creates no support or maintenance obligation for any person or organization.
