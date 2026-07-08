# Interactive installer

> [!CAUTION]
> **UNSUPPORTED, NON-PRODUCTION DEMONSTRATION ONLY.** The installer and poller are not supported, approved, endorsed, maintained, or warranted by Damon Cassell, Cato Networks, Cribl, any employer, contributor, vendor, partner, or anyone else. There is no license grant. Read [`../DISCLAIMER.md`](../DISCLAIMER.md).

The repository includes [`install.sh`](../install.sh), an interactive wrapper for a clean demonstration installation beside an existing non-production Cribl Stream Docker deployment.

The installer reads its answers directly from `/dev/tty`. This allows it to remain interactive even when the script itself is supplied to Bash through a pipe.

## Recommended customer command

Download the script, inspect it, and then run it:

```bash
curl -fsSLo /tmp/catocribbler-install.sh \
  https://raw.githubusercontent.com/dzcassell/catocribbler/main/install.sh

less /tmp/catocribbler-install.sh
sudo bash /tmp/catocribbler-install.sh
```

This is safer than executing a mutable remote script without review.

## One-line command

For a direct interactive installation:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/dzcassell/catocribbler/main/install.sh \
  | sudo bash
```

The prompts still work because the installer reads responses from `/dev/tty`, not from the pipe connected to standard input.

## Reproducible pinned installation

For a customer demonstration, pin both the downloaded installer and the repository checkout to a reviewed commit:

```bash
INSTALL_REF=<reviewed-commit-sha>

curl -fsSL \
  "https://raw.githubusercontent.com/dzcassell/catocribbler/${INSTALL_REF}/install.sh" \
  | sudo env CATOCRIBBLER_REF="${INSTALL_REF}" bash
```

Replace `<reviewed-commit-sha>` with the commit approved for the demonstration.

## What the installer asks

The installer prompts for:

- Acceptance of the unsupported demonstration disclaimer
- Installation directory, defaulting to `/opt/cribbler`
- Cato GraphQL endpoint
- Numeric Cato account ID
- Cribl connection model
- Cribl host or Docker network and service name
- Cribl Syslog TCP port, defaulting to `9514`
- Whether Cribl TLS is enabled
- TLS server name and CA chain when applicable
- Polling interval, defaulting to 30 seconds
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
14. Records the installed commit in `INSTALLATION_INFO.txt`.
15. Leaves continuous polling stopped unless the evaluator types `START` after the backlog warning.

## Supported environment overrides

The command can override installer defaults:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/dzcassell/catocribbler/main/install.sh \
  | sudo env \
      CATOCRIBBLER_REF=main \
      CATOCRIBBLER_INSTALL_DIR=/opt/cribbler \
      CATOCRIBBLER_CATO_API_URL=https://api.us1.catonetworks.com/api/v1/graphql2 \
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

The installer prints the selected paths and records non-secret installation metadata in:

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
