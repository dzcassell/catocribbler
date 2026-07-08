# Fresh installation beside an existing Cribl Docker deployment

> [!CAUTION]
> **UNSUPPORTED, NON-PRODUCTION DEMONSTRATION ONLY.** This repository is not supported, approved, endorsed, maintained, or warranted by Damon Cassell, Cato Networks, Cribl, any employer, contributor, vendor, partner, or anyone else. There is no license grant. Do not use this code in production. Read [`../DISCLAIMER.md`](../DISCLAIMER.md).

This guide describes a fresh installation of the experimental `cato-events-poller` beside an existing non-production Cribl Stream Docker deployment.

The preferred installation method is the interactive [`install.sh`](../install.sh) wrapper. It creates the selected directory, writes fresh local configuration, stores the Cato key as a Docker secret source file, builds the image, runs independent Cato and Cribl preflights, optionally sends a synthetic event, and leaves continuous polling stopped until the evaluator explicitly types `START`.

The default installation directory is:

```text
/opt/cribbler
```

## 1. Preconditions

Before installing, confirm all of the following:

- The host is an isolated non-production Linux system.
- Docker Engine is installed and running.
- Docker Compose v2 is available through `docker compose`.
- Git and Python 3 are installed.
- Cribl Stream is already running in Docker.
- A non-production Cribl Worker or single-instance container can receive TCP syslog.
- The test Syslog Source is enabled, committed, and deployed.
- The selected test Destination is isolated from production analytics, automation, retention, and alerting.
- The Cato account and EventsFeed data are approved for this demonstration.
- The evaluator understands that an empty marker can replay retained EventsFeed records in pages of up to 3,000.

Verify the host:

```bash
docker version
docker compose version
git --version
python3 --version
```

Inspect Cribl:

```bash
docker ps \
  --filter 'name=cribl' \
  --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
```

Record either:

- The Docker host IP or DNS name and published Syslog TCP port, or
- The existing non-production Cribl Docker network and Cribl service/container name.

Do not use `127.0.0.1` or `localhost` as the Cribl host from inside the poller container.

## 2. Create a fresh Cato service principal

For a shared demonstration, use a dedicated service principal rather than a personal administrator identity.

In the Cato Management Application:

1. Go to **Account > Administrators**.
2. Select **New**.
3. Select **Create New**.
4. Select **Create as Service Principal**.
5. Use a descriptive name such as:

   ```text
   Cribl EventsFeed Demo
   ```

6. Assign Viewer or equivalent read-only permissions.
7. Limit the scope to the approved test account and only the resources required for the demonstration.
8. Apply the configuration.

## 3. Create a fresh Service API Key

1. Go to **Resources > Service API Keys**.
2. Select **New**.
3. Select the new service principal.
4. Use a descriptive key name such as:

   ```text
   catocribbler-demo-YYYYMMDD
   ```

5. Select **Downgrade to View**.
6. Restrict allowed source IPs to the test host's public egress IP where practical.
7. Set a short expiration.
8. Apply the configuration.
9. Copy the key immediately into an approved password manager.

The installer requests the key twice without displaying it and stores it only in:

```text
<install-directory>/poller/secrets/cato_api_key
```

Do not paste the key into chat, tickets, issue trackers, shell history, or documentation.

## 4. Review the installer

For a customer-facing demonstration, use a reviewed commit rather than mutable `main`.

Set the reviewed commit:

```bash
INSTALL_REF=<reviewed-commit-sha>
```

Download and inspect the exact installer from that commit:

```bash
curl -fsSLo /tmp/catocribbler-install.sh \
  "https://raw.githubusercontent.com/dzcassell/catocribbler/${INSTALL_REF}/install.sh"

less /tmp/catocribbler-install.sh
```

Run the reviewed script and require the repository checkout to use the same commit:

```bash
sudo env \
  CATOCRIBBLER_REF="${INSTALL_REF}" \
  bash /tmp/catocribbler-install.sh
```

A direct one-line invocation is also possible:

```bash
curl -fsSL \
  "https://raw.githubusercontent.com/dzcassell/catocribbler/${INSTALL_REF}/install.sh" \
  | sudo env \
      CATOCRIBBLER_REF="${INSTALL_REF}" \
      bash
```

The installer reads answers from `/dev/tty`, so prompts remain interactive even when the script is piped into Bash.

## 5. Installer questions

The installer asks for:

1. Exact acceptance text:

   ```text
   I UNDERSTAND
   ```

2. Installation directory, default:

   ```text
   /opt/cribbler
   ```

3. Cato GraphQL API endpoint, default:

   ```text
   https://api.us1.catonetworks.com/api/v1/graphql2
   ```

4. Numeric Cato account ID.
5. Cribl connection method:
   - Published Docker-host TCP port, or
   - Shared external Docker network.
6. Cribl host, container name, service name, or network alias.
7. Cribl Syslog TCP port, default `9514`.
8. Whether TLS is enabled.
9. TLS server name and PEM CA chain when TLS is used.
10. Polling interval, default 30 seconds.
11. The new Cato API key, entered twice without echo.
12. Whether to create the installation.
13. Whether to send one synthetic test event.
14. Whether to start continuous polling.

The installer rejects:

- Relative paths
- `/`
- `/opt`
- Existing non-empty installation directories
- Invalid numeric account IDs
- Invalid TCP ports
- Missing external Docker networks
- Missing TLS CA files
- Mismatched API-key entries

## 6. What the installer creates

With the default path, the installation resembles:

```text
/opt/cribbler/
├── DISCLAIMER.md
├── INSTALLATION_INFO.txt
├── README.md
├── install.sh
├── poller/
│   ├── .dockerignore
│   ├── .env
│   ├── compose.yaml
│   ├── compose.override.yaml     # shared-network model only
│   ├── Dockerfile
│   ├── poller.py
│   ├── requirements.txt
│   ├── secrets/
│   │   ├── cato_api_key
│   │   └── cribl_ca.pem
│   └── state/
│       └── marker.txt            # created after successful delivery
└── docs/
```

The local files are protected as follows:

- `.env`: mode `0600`
- API key: owner UID/GID `10001`, mode `0400`
- Cribl CA file: owner UID/GID `10001`, mode `0400`
- Marker directory: owner UID/GID `10001`, mode `0700`

The Docker build context excludes `.env`, `secrets/`, `state/`, and `compose.override.yaml`.

## 7. Automatic preflights

Before continuous polling, the installer performs:

### Cato API preflight

The installed poller code:

- Reads the new secret file.
- Authenticates with `x-api-key`.
- Calls EventsFeed for the configured account.
- Decodes the returned records.
- Does not send them to Cribl.
- Does not write the marker.

Expected result:

```text
CATO API PREFLIGHT PASS fetched=N decoded=N current_marker_len=0 returned_marker_len=N
```

### Cribl connection preflight

The installed poller code opens the configured TCP or TLS socket to Cribl.

Expected result:

```text
CRIBL CONNECTION PREFLIGHT PASS host=<host> port=9514 tls=<true-or-false> peer=<address>
```

### Optional synthetic test

The installer can send one RFC 5424 event with:

```text
event_type=Catocribbler Installer Synthetic Test
```

Confirm that this event:

1. Reaches the intended Cribl Syslog Source.
2. Matches the `cato_events_route` Route.
3. Passes through `cato_normalize`.
4. Reaches the isolated test Destination.

## 8. Starting continuous polling

The installer does not start polling automatically after preflights.

It displays the replay warning and requires the evaluator to type:

```text
START
```

Pressing Enter leaves the installation built and tested but stopped.

Start it later with:

```bash
cd /opt/cribbler/poller
docker compose up -d
```

Watch the first cycles:

```bash
docker compose logs -f cato-events-poller
```

A successful cycle resembles:

```text
INFO starting marker_len=0
INFO Fetched=3000 Sent=3000 marker_len=180
INFO Fetched=425 Sent=425 marker_len=180
```

A full 3,000-record page is drained immediately. This can create significant volume.

`Fetched=N Sent=N` proves that the poller wrote the records to the Cribl socket. It does not prove that Cribl parsed, routed, transformed, persisted, or delivered them correctly.

## 9. Post-install validation

Run:

```bash
cd /opt/cribbler/poller

docker compose ps
docker compose logs --tail=100 cato-events-poller

stat -c 'uid=%u gid=%g mode=%a size=%s path=%n' \
  .env \
  secrets/cato_api_key \
  secrets/cribl_ca.pem \
  state \
  state/marker.txt 2>/dev/null || true

git -C /opt/cribbler rev-parse HEAD
git -C /opt/cribbler status --short
```

Expected results:

- Container state is `Up` when polling was started.
- Logs contain matching `Fetched` and `Sent` counts.
- `state/marker.txt` exists after a successfully delivered page.
- The Git commit matches the reviewed commit.
- `git status --short` does not list `.env`, secrets, state, installation metadata, or Compose overrides.

Also confirm in Cribl:

- Source event counts increase.
- Live Capture shows `appname=cato-events`.
- Route match counts increase.
- Pipeline adds `cribl_pipeline=cato_normalize`.
- The isolated Destination receives events.
- Queues remain healthy.

## 10. Useful commands

```bash
cd /opt/cribbler/poller
```

Status:

```bash
docker compose ps
```

Logs:

```bash
docker compose logs -f cato-events-poller
```

Stop:

```bash
docker compose stop cato-events-poller
```

Start:

```bash
docker compose up -d
```

Remove only the poller container and private Compose network while preserving local files:

```bash
docker compose down
```

## 11. Cleanup after the demonstration

1. Stop and remove the poller:

   ```bash
   cd /opt/cribbler/poller
   docker compose down
   ```

2. Revoke the Cato Service API Key.
3. Remove the demonstration-only service principal if it is no longer needed.
4. Remove test-only Cribl Source, Route, Pipeline, and Destination objects when appropriate.
5. Remove the poller from any shared Docker network.
6. Destroy copied keys, CA files, marker state, backups, and test data according to policy.
7. Remove the installation directory:

   ```bash
   rm -rf -- /opt/cribbler
   ```

## Manual installation

The interactive wrapper is the preferred method because it applies the current directory, secret, networking, preflight, and replay safeguards consistently.

For unusual environments, read [`INSTALLER.md`](INSTALLER.md), [`CRIBL.md`](CRIBL.md), and [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md), then reproduce the same controls manually. Do not omit the independent Cato and Cribl preflights.
