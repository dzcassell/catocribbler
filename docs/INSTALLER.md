# Interactive installer

> [!CAUTION]
> **UNSUPPORTED, NON-PRODUCTION DEMONSTRATION ONLY.** The installer and poller are not supported, approved, endorsed, maintained, or warranted by Damon Cassell, Cato Networks, Cribl, any employer, contributor, vendor, partner, or anyone else. There is no license grant. Read [`../DISCLAIMER.md`](../DISCLAIMER.md).

The repository includes [`install.sh`](../install.sh), an interactive wrapper for a clean demonstration installation beside an existing non-production Cribl Stream Docker deployment.

The installer reads answers directly from `/dev/tty`, so its prompts remain interactive when the script is supplied to Bash through a pipe.

## Recommended customer command

```bash
INSTALL_REF=<reviewed-commit-sha>

curl -fsSLo /tmp/catocribbler-install.sh \
  "https://raw.githubusercontent.com/dzcassell/catocribbler/${INSTALL_REF}/install.sh"

less /tmp/catocribbler-install.sh

sudo env \
  CATOCRIBBLER_REF="${INSTALL_REF}" \
  bash /tmp/catocribbler-install.sh
```

This pins both the downloaded installer and repository checkout to the same reviewed commit.

## Direct one-line command

```bash
INSTALL_REF=<reviewed-commit-sha>

curl -fsSL \
  "https://raw.githubusercontent.com/dzcassell/catocribbler/${INSTALL_REF}/install.sh" \
  | sudo env \
      CATOCRIBBLER_REF="${INSTALL_REF}" \
      bash
```

## Installer defaults

| Setting | Default |
|---|---|
| Installation directory | `/opt/cribbler` |
| Cato GraphQL API URL | `https://api.catonetworks.com/api/v1/graphql` |
| Cribl connection method | Auto-detected published host TCP port |
| Cribl Syslog TCP port | `9514` |
| Cribl TLS | Disabled |
| Poll interval | 30 seconds |
| Start continuous polling | No, unless the evaluator types `START` |

## Automatic Cribl listener detection

Before asking the evaluator to enter any Cribl networking information, the installer:

1. Finds running Docker containers whose names contain `cribl`.
2. Checks those containers for a published `9514/tcp` listener.
3. Detects the Docker host's primary IPv4 address.
4. Converts a wildcard mapping such as `0.0.0.0:9514` into a usable address such as `192.168.40.15:9514`.
5. Shows the detected container, Docker mapping, and address.
6. Asks only:

   ```text
   Use this detected Cribl listener [Y/n]:
   ```

For a typical installation, the evaluator presses Enter. No IP address or Docker network name must be discovered manually.

Example:

```text
The installer found a running Cribl container with a published Syslog listener:

  Cribl container:            cribl-worker
  Docker port mapping:        0.0.0.0:9514
  Address the poller will use: 192.168.40.15:9514

Use this detected Cribl listener [Y/n]:
```

## When detection does not find the intended listener

The installer offers two alternatives only when:

- No running `cribl*` container publishes `9514/tcp`, or
- The evaluator rejects the detected listener.

### 1. Different published host address and port

The installer supplies its detected primary host address as the default when available. The evaluator normally needs to provide only a non-default published port.

### 2. Shared external Docker network, advanced fallback

Use this when Cribl does not publish the Syslog TCP port or direct container-to-container connectivity is specifically required.

The poller joins an existing non-production Cribl Docker network and connects using the Cribl container, service, or network-alias name. This method is less portable and gives the poller access to other services exposed on that network.

The installer lists available Docker networks and validates the selected one.

## What the installer asks

The installer prompts for:

- Acceptance of the unsupported demonstration disclaimer
- Installation directory
- Cato GraphQL endpoint
- Numeric Cato account ID
- Confirmation of an automatically detected Cribl listener, when found
- Alternative Cribl networking only when detection fails or is rejected
- Whether Cribl TLS is enabled
- TLS server name and CA chain when applicable
- Polling interval
- The new Cato API key, entered twice without terminal echo
- Whether to send one synthetic Cribl event
- Whether to start continuous EventsFeed polling

## What the installer does

The wrapper:

1. Requires root, Git, Python 3, Docker, and Docker Compose v2.
2. Refuses `/`, `/opt`, relative paths, and non-empty installation directories.
3. Creates the selected directory if needed.
4. Clones the repository and checks out `CATOCRIBBLER_REF`, defaulting to `main`.
5. Verifies that `.dockerignore` excludes `.env`, `secrets/`, and `state/`.
6. Creates a root-readable `.env` file.
7. Stores the Cato API key only in `poller/secrets/cato_api_key`.
8. Creates a new empty marker directory.
9. Auto-detects a published Cribl listener when possible.
10. Creates a Compose override only when the shared-network model is selected.
11. Builds the image with `--pull --no-cache`.
12. Calls the poller's Cato API code without sending records or updating the marker.
13. Opens a TCP or TLS connection to the existing Cribl Syslog Source.
14. Optionally sends one synthetic RFC 5424 event.
15. Records the installed commit and selected connection method in `INSTALLATION_INFO.txt`.
16. Leaves continuous polling stopped unless the evaluator types `START` after the backlog warning.

## Supported environment overrides

```bash
curl -fsSL \
  https://raw.githubusercontent.com/dzcassell/catocribbler/main/install.sh \
  | sudo env \
      CATOCRIBBLER_REF=main \
      CATOCRIBBLER_INSTALL_DIR=/opt/cribbler \
      CATOCRIBBLER_CATO_API_URL=https://api.catonetworks.com/api/v1/graphql \
      CATOCRIBBLER_CRIBL_PORT=9514 \
      CATOCRIBBLER_POLL_INTERVAL=30 \
      bash
```

Environment overrides set defaults only. The installer still displays and confirms the resulting values.

## First-run warning

A new installation has no EventsFeed marker. Starting continuous polling can retrieve all events currently retained by EventsFeed, in consecutive pages of up to 3,000 records.

The installer therefore runs authentication and Cribl connectivity checks first and requires the evaluator to type:

```text
START
```

before continuous polling begins.

## After installation

The installer records non-secret installation metadata in:

```text
<install-directory>/INSTALLATION_INFO.txt
```

Typical management commands:

```bash
cd /opt/cribbler/poller

docker compose ps
docker compose logs -f cato-events-poller
docker compose up -d
docker compose down
```

The Cato API key is stored in:

```text
/opt/cribbler/poller/secrets/cato_api_key
```

Do not display, copy into tickets, or commit that file.
