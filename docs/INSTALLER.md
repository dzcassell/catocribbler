# Interactive installer

> [!CAUTION]
> **UNSUPPORTED, NON-PRODUCTION DEMONSTRATION ONLY.** The installer and poller are not supported, approved, endorsed, maintained, or warranted by Damon Cassell, Cato Networks, Cribl, any employer, contributor, vendor, partner, or anyone else. There is no license grant. Read [`../DISCLAIMER.md`](../DISCLAIMER.md).

The repository includes [`install.sh`](../install.sh), an interactive wrapper for a clean demonstration installation beside an existing non-production Cribl Stream Docker deployment.

The installer reads answers directly from `/dev/tty`, so its prompts remain interactive when the script is supplied to Bash through a pipe.

## Recommended customer command

Download the script, inspect it, and then run it:

```bash
INSTALL_REF=<reviewed-commit-sha>

curl -fsSLo /tmp/catocribbler-install.sh \
  "https://raw.githubusercontent.com/dzcassell/catocribbler/${INSTALL_REF}/install.sh"

less /tmp/catocribbler-install.sh

sudo env \
  CATOCRIBBLER_REF="${INSTALL_REF}" \
  bash /tmp/catocribbler-install.sh
```

This pins both the downloaded installer and the repository checkout to the same reviewed commit.

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
| Cribl connection method | Published host TCP port |
| Cribl Syslog TCP port | `9514` |
| Cribl TLS | Disabled |
| Poll interval | 30 seconds |
| Start continuous polling | No, unless the evaluator types `START` |

## Cribl connection methods

The installer explains both choices before prompting.

### 1. Published host TCP port, recommended default

Use this when the Cribl container publishes the Syslog Source port to the Docker host, for example:

```text
0.0.0.0:9514->9514/tcp
```

Enter the Docker host's LAN IP address or DNS name.

This is the recommended default because it:

- Is simpler to explain and troubleshoot.
- Does not attach the poller to Cribl's internal Docker network.
- Does not depend on local Docker network names or aliases.
- Works when the poller runs on the same host or another reachable test host.

Do not enter `localhost` or `127.0.0.1`; inside the poller container those addresses refer to the poller itself.

### 2. Shared external Docker network, advanced fallback

Use this when:

- Cribl does not publish the Syslog TCP port, or
- Direct container-to-container connectivity is specifically required.

The poller joins an existing non-production Cribl Docker network and connects using the Cribl container, service, or network-alias name.

This method:

- Depends on local Docker network names and aliases.
- Gives the poller access to other services exposed on that network.
- Requires the selected network to exist before installation.
- Is less portable between customer environments.

The installer lists available Docker networks and validates the selected network.

**Recommendation:** press Enter for option 1 unless the Cribl Syslog TCP port is not published or the deployment specifically requires a shared Docker network.

## What the installer asks

The installer prompts for:

- Acceptance of the unsupported demonstration disclaimer
- Installation directory
- Cato GraphQL endpoint
- Numeric Cato account ID
- Cribl connection method
- Cribl host or Docker network and service name
- Cribl Syslog TCP port
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
9. Creates a Compose override when the shared-network model is selected.
10. Builds the image with `--pull --no-cache`.
11. Calls the poller's Cato API code without sending records or updating the marker.
12. Opens a TCP or TLS connection to the existing Cribl Syslog Source.
13. Optionally sends one synthetic RFC 5424 event.
14. Records the installed commit and selected connection method in `INSTALLATION_INFO.txt`.
15. Leaves continuous polling stopped unless the evaluator types `START` after the backlog warning.

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

Typical management commands are:

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
