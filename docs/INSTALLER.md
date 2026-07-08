# Interactive installer

> [!CAUTION]
> **UNSUPPORTED, NON-PRODUCTION DEMONSTRATION ONLY.** The installer and poller are not supported, approved, endorsed, maintained, or warranted by Damon Cassell, Cato Networks, Cribl, any employer, contributor, vendor, partner, or anyone else. There is no license grant. Read [`../DISCLAIMER.md`](../DISCLAIMER.md).

## Run the installer

From an interactive Linux terminal on the Docker host, run:

```bash
curl -fsSL https://raw.githubusercontent.com/dzcassell/catocribbler/main/install.sh | sudo bash
```

No Git commit, branch name, SHA, tag, or environment variable is required from the customer.

The installer downloads the current `main` version, installs it, and records the exact installed commit automatically in:

```text
/opt/cribbler/INSTALLATION_INFO.txt
```

That information is for troubleshooting only.

## What to have ready

### Cato

- Numeric Cato account ID
- Fresh read-only Service API Key
- Approval to use EventsFeed for the demonstration

### Cribl

- Running non-production Cribl Worker or single-instance container
- Enabled TCP Syslog Source, normally on port `9514`
- Test Route and Pipeline
- Isolated test Destination

## Installer defaults

| Setting | Default |
|---|---|
| Installation directory | `/opt/cribbler` |
| Cato GraphQL API URL | `https://api.catonetworks.com/api/v1/graphql` |
| Cribl connection | Automatically detected published TCP listener |
| Cribl Syslog TCP port | `9514` |
| Cribl TLS | Disabled |
| Poll interval | 30 seconds |
| Start continuous polling | No, unless the operator types `START` |

## Automatic Cribl detection

Before asking for any Cribl networking information, the installer:

1. Finds running containers whose names contain `cribl`.
2. Checks those containers for a published `9514/tcp` listener.
3. Detects the Docker host's primary IPv4 address.
4. Converts a wildcard Docker mapping such as `0.0.0.0:9514` into a usable address.
5. Shows the detected container and endpoint.
6. Asks whether to use it.

Example:

```text
The installer found a running Cribl container with a published Syslog listener:

  Cribl container:            cribl-worker
  Docker port mapping:        0.0.0.0:9514
  Address the poller will use: 192.168.40.15:9514

Use this detected Cribl listener [Y/n]:
```

For a normal installation, press Enter.

Manual networking questions appear only when detection fails or the detected listener is rejected.

## Installer questions

The normal sequence is:

1. Type `I UNDERSTAND` to accept the demonstration disclaimer.
2. Press Enter to accept `/opt/cribbler`, or enter another empty absolute path.
3. Press Enter to accept the default Cato GraphQL endpoint, or enter the endpoint assigned to the tenant.
4. Enter the numeric Cato account ID.
5. Press Enter to accept the detected Cribl listener.
6. Answer whether TLS is used.
7. Press Enter to accept a 30-second polling interval.
8. Paste the Cato API key twice. The key is not displayed.
9. Confirm creation of the installation.
10. Confirm whether to send a synthetic event.
11. Type `START` only after the Cribl test path is ready.

## What the installer does

The installer:

1. Checks for root, Git, Python 3, Docker, and Docker Compose v2.
2. Refuses unsafe or non-empty installation directories.
3. Creates the selected directory.
4. Clones the current `main` branch.
5. Verifies that Docker build exclusions protect `.env`, secrets, and state.
6. Creates the local `.env`, secret, certificate, and marker directories.
7. Stores the API key only in `poller/secrets/cato_api_key`.
8. Detects the published Cribl listener when possible.
9. Builds the poller image with `--pull --no-cache`.
10. Runs a Cato API preflight without sending records or updating the marker.
11. Opens the configured Cribl TCP or TLS socket.
12. Optionally sends one synthetic RFC 5424 event.
13. Records the exact installed commit automatically.
14. Leaves continuous polling stopped unless the operator types `START`.

## Expected preflight results

Cato:

```text
CATO API PREFLIGHT PASS fetched=N decoded=N current_marker_len=0 returned_marker_len=N
```

Cribl:

```text
CRIBL CONNECTION PREFLIGHT PASS host=<host> port=9514 tls=<true-or-false> peer=<address>
```

Synthetic event:

```text
SYNTHETIC CRIBL EVENT SENT
```

## First-run warning

A new installation has no EventsFeed marker. Starting continuous polling can retrieve all retained EventsFeed records, potentially in consecutive pages of up to 3,000.

The installer requires:

```text
START
```

before polling begins. Pressing Enter leaves the installation built and tested but stopped.

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

Do not display, copy into tickets, or commit that file.
