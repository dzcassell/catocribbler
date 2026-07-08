# Fresh installation beside an existing Cribl Docker deployment

> [!CAUTION]
> **UNSUPPORTED, NON-PRODUCTION DEMONSTRATION ONLY.** This repository is not supported, approved, endorsed, maintained, or warranted by Damon Cassell, Cato Networks, Cribl, any employer, contributor, vendor, partner, or anyone else. There is no license grant. Do not use this code in production. Read [`../DISCLAIMER.md`](../DISCLAIMER.md).

This guide describes a fresh installation of the experimental `cato-events-poller` beside an existing non-production Cribl Stream Docker deployment.

The preferred installation method is the interactive [`install.sh`](../install.sh) wrapper. It creates the selected directory, writes fresh local configuration, stores the Cato key as a Docker secret source file, builds the image, runs independent Cato and Cribl preflights, optionally sends a synthetic event, and leaves continuous polling stopped until the evaluator explicitly types `START`.

## 1. Defaults

| Setting | Default |
|---|---|
| Installation directory | `/opt/cribbler` |
| Cato GraphQL API URL | `https://api.catonetworks.com/api/v1/graphql` |
| Cribl connection method | Auto-detected published host TCP port |
| Cribl Syslog TCP port | `9514` |
| Cribl TLS | Disabled |
| Poll interval | 30 seconds |

## 2. Preconditions

Before installing, confirm:

- The host is an isolated non-production Linux system.
- Docker Engine is installed and running.
- Docker Compose v2 is available through `docker compose`.
- Git and Python 3 are installed.
- Cribl Stream is already running in Docker.
- A non-production Cribl Worker or single-instance container can receive TCP syslog.
- The test Syslog Source is enabled, committed, and deployed.
- The test Destination is isolated from production analytics, automation, retention, and alerting.
- The Cato account and EventsFeed data are approved for the demonstration.
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

## 3. How Cribl connectivity is selected

### Automatic published-listener detection

Before asking for any Cribl address, the installer:

1. Finds running containers whose names contain `cribl`.
2. Checks for a published `9514/tcp` listener.
3. Detects the Docker host's primary IPv4 address.
4. Converts a wildcard mapping such as `0.0.0.0:9514` into a usable address such as `192.168.40.15:9514`.
5. Shows the detected container, mapping, and address.
6. Asks whether to use it.

Typical prompt:

```text
The installer found a running Cribl container with a published Syslog listener:

  Cribl container:            cribl-worker
  Docker port mapping:        0.0.0.0:9514
  Address the poller will use: 192.168.40.15:9514

Use this detected Cribl listener [Y/n]:
```

For a normal installation, press Enter. No IP address, port, Docker network, or container alias needs to be discovered manually.

### Alternative 1: Different published host address and port

Use this only when the detected listener is not the intended Cribl Source or when Cribl uses another published port.

The installer supplies its detected primary host address as the default when available.

### Alternative 2: Shared external Docker network

Use this only when Cribl does not publish the Syslog TCP port or direct container-to-container connectivity is specifically required.

The poller joins an existing non-production Cribl Docker network and connects using the Cribl container, service, or network-alias name.

This method:

- Depends on local Docker network names and aliases.
- Gives the poller access to other services exposed on that network.
- Is less portable between customer environments.
- Requires the network to exist before installation.

## 4. Create a fresh Cato service principal

In the Cato Management Application:

1. Go to **Account > Administrators**.
2. Select **New**.
3. Select **Create New**.
4. Select **Create as Service Principal**.
5. Use a name such as:

   ```text
   Cribl EventsFeed Demo
   ```

6. Assign Viewer or equivalent read-only permissions.
7. Limit the scope to the approved test account and required resources.
8. Apply the configuration.

## 5. Create a fresh Service API Key

1. Go to **Resources > Service API Keys**.
2. Select **New**.
3. Select the new service principal.
4. Use a descriptive name such as:

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

## 6. Download and inspect a pinned installer

Use a reviewed commit rather than mutable `main`:

```bash
INSTALL_REF=<reviewed-commit-sha>

curl -fsSLo /tmp/catocribbler-install.sh \
  "https://raw.githubusercontent.com/dzcassell/catocribbler/${INSTALL_REF}/install.sh"

less /tmp/catocribbler-install.sh
```

Run the reviewed script and force the repository checkout to use the same commit:

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

The installer reads answers from `/dev/tty`, so prompts remain interactive through a pipe.

## 7. Installer questions

The installer asks for:

1. Exact acceptance text:

   ```text
   I UNDERSTAND
   ```

2. Installation directory, default `/opt/cribbler`.
3. Cato GraphQL API URL, default:

   ```text
   https://api.catonetworks.com/api/v1/graphql
   ```

4. Numeric Cato account ID.
5. Confirmation of an automatically detected Cribl listener, when found.
6. Alternative Cribl networking only when detection fails or is rejected.
7. Whether TLS is enabled.
8. TLS server name and PEM CA chain when TLS is used.
9. Polling interval, default 30 seconds.
10. The new Cato API key, entered twice without echo.
11. Whether to create the installation.
12. Whether to send one synthetic test event.
13. Whether to start continuous polling.

The installer rejects relative paths, `/`, `/opt`, non-empty install directories, invalid account IDs, invalid ports, missing Docker networks, missing CA files, and mismatched API-key entries.

## 8. What the installer creates

With the default path:

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

Local protection:

- `.env`: mode `0600`
- API key: owner UID/GID `10001`, mode `0400`
- Cribl CA file: owner UID/GID `10001`, mode `0400`
- Secret and marker directories: owner UID/GID `10001`, mode `0700`

The Docker build context excludes `.env`, `secrets/`, `state/`, and `compose.override.yaml`.

## 9. Automatic preflights

### Cato API preflight

The installed poller code authenticates, calls EventsFeed, and decodes one page without sending events to Cribl or updating the marker.

Expected result:

```text
CATO API PREFLIGHT PASS fetched=N decoded=N current_marker_len=0 returned_marker_len=N
```

### Cribl connection preflight

The installed poller code opens the configured TCP or TLS socket.

Expected result:

```text
CRIBL CONNECTION PREFLIGHT PASS host=<host> port=9514 tls=<true-or-false> peer=<address>
```

### Optional synthetic test

The installer can send one RFC 5424 event with:

```text
event_type=Catocribbler Installer Synthetic Test
```

Confirm the event reaches the intended Source, Route, Pipeline, and isolated Destination.

## 10. Start continuous polling

The installer requires the evaluator to type:

```text
START
```

before continuous polling begins. Pressing Enter leaves the installation built and tested but stopped.

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

A full 3,000-record page is drained immediately and can create significant volume.

`Fetched=N Sent=N` proves only that the poller wrote records to the Cribl socket. It does not prove downstream parsing, routing, persistence, or delivery.

## 11. Post-install validation

```bash
cd /opt/cribbler/poller

docker compose ps
docker compose logs --tail=100 cato-events-poller

stat -c 'uid=%u gid=%g mode=%a size=%s path=%n' \
  .env \
  secrets \
  secrets/cato_api_key \
  secrets/cribl_ca.pem \
  state \
  state/marker.txt 2>/dev/null || true

git -C /opt/cribbler rev-parse HEAD
git -C /opt/cribbler status --short
```

Expected:

- Container is `Up` when polling was started.
- Logs contain matching `Fetched` and `Sent` counts.
- The marker exists after a successfully delivered page.
- The Git commit matches the reviewed commit.
- Git status does not list local configuration, secrets, state, metadata, or overrides.

Also confirm in Cribl:

- Source event counts increase.
- Live Capture shows `appname=cato-events`.
- Route match counts increase.
- Pipeline adds `cribl_pipeline=cato_normalize`.
- The isolated Destination receives events.
- Queues remain healthy.

## 12. Cleanup

```bash
cd /opt/cribbler/poller
docker compose down
```

Then revoke the Cato Service API Key, remove the demonstration-only service principal when appropriate, remove test-only Cribl objects, detach external Docker networks, destroy copied credentials and state according to policy, and remove the installation directory when no longer required.
