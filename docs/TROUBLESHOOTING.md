# Troubleshooting the unsupported Cato-to-Cribl demonstration

> [!CAUTION]
> **UNSUPPORTED, NON-PRODUCTION DEMONSTRATION ONLY.** This material is not a support service, supported runbook, official integration guide, or assurance that the code can be made safe or reliable. Damon Cassell, Cato Networks, Cribl, employers, contributors, vendors, partners, and all other parties provide no support, warranty, maintenance, incident response, or obligation to help. There is no license grant. Read [`../DISCLAIMER.md`](../DISCLAIMER.md).

This guide covers both the interactive installer and an installed `cato-events-poller` deployment.

The default installation directory is `/opt/cribbler`, but the installer allows another absolute path. Set the actual path before running installed-system commands:

```bash
INSTALL_DIR=${INSTALL_DIR:-/opt/cribbler}
POLLER_DIR="${INSTALL_DIR}/poller"
```

## 1. Stop if this is production

Do not continue if the Cato account, Cribl Worker Group, Source, Route, Pipeline, Destination, Docker host, or network is production.

Use only:

- An approved test account
- An isolated non-production Cribl environment
- A dedicated short-lived Cato key
- Synthetic or specifically approved test data
- An isolated test Destination
- A documented cleanup and key-revocation plan

## 2. Fast triage order

Troubleshoot in this order:

1. Installer prerequisites and directory creation
2. Cato endpoint, account ID, key, permissions, and source-IP restrictions
3. Poller image build
4. Poller-to-Cribl DNS and TCP connectivity
5. TLS validation when enabled
6. Cribl Syslog Source
7. Synthetic event
8. Cribl Route
9. Cribl Pipeline
10. Cribl Destination
11. Continuous polling and marker state

The first failing layer is the one to investigate. Regenerating an API key will not repair a Docker network, despite the universal human instinct to rotate credentials whenever networking becomes emotionally difficult.

## 3. Interactive installer failures

### `An interactive terminal is required`

The installer needs readable and writable `/dev/tty` because it reads prompts there when the script is piped to Bash.

Run it from an interactive SSH or console session:

```bash
test -r /dev/tty && test -w /dev/tty && echo 'TTY PASS'
```

Do not run it through a non-interactive scheduler, detached shell, or automation system without adapting the installer.

### `Run this installer as root`

Use:

```bash
sudo bash /tmp/catocribbler-install.sh
```

or:

```bash
curl -fsSL <pinned-installer-url> | sudo env CATOCRIBBLER_REF=<commit> bash
```

### Missing `git`, `docker`, or `python3`

Verify:

```bash
git --version
docker version
docker compose version
python3 --version
```

The installer requires Docker Compose v2 through `docker compose`, not the retired standalone `docker-compose` command.

### Installation directory already exists and is not empty

The installer refuses to overwrite an existing installation.

Inspect it:

```bash
ls -la /opt/cribbler
```

Choose another empty directory or remove the old demonstration after preserving any approved marker state and revoking its credentials.

### Installer stopped after cloning or building

The partial installation remains in the selected directory for inspection.

```bash
cd "${INSTALL_DIR}"
git status --short
git rev-parse HEAD

cd poller
docker compose config
docker compose ps -a
docker compose logs --tail=100 2>/dev/null || true
```

Remove the partial installation only after collecting the necessary diagnostics and confirming no marker or credential must be preserved.

## 4. Inspect the existing Cribl Docker environment

```bash
docker ps \
  --filter 'name=cribl' \
  --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
```

For a selected test Worker or single-instance container:

```bash
CRIBL_CONTAINER=cribl-worker

docker inspect "${CRIBL_CONTAINER}" \
  --format 'Name={{.Name}}
Image={{.Config.Image}}
Networks={{json .NetworkSettings.Networks}}
PublishedPorts={{json .NetworkSettings.Ports}}'

docker port "${CRIBL_CONTAINER}"
```

Do not target a Leader management port unless that node intentionally processes test data.

## 5. Docker connectivity models

### Published host port

Use the Docker host's LAN/test-network IP or DNS name when Cribl publishes the Syslog port:

```text
0.0.0.0:9514->9514/tcp
```

The poller settings should resemble:

```dotenv
CRIBL_SYSLOG_HOST=192.0.2.25
CRIBL_SYSLOG_PORT=9514
```

Do not use `localhost` or `127.0.0.1`; inside the poller container those addresses refer to the poller itself.

### Shared external Docker network

The installer creates `poller/compose.override.yaml` when this option is selected.

Inspect it:

```bash
cat "${POLLER_DIR}/compose.override.yaml"
```

Confirm the external network exists:

```bash
docker network inspect <cribl-test-network-name> >/dev/null
```

Confirm the Cribl container is attached:

```bash
docker inspect cribl-worker \
  --format '{{json .NetworkSettings.Networks}}'
```

The configured Cribl host must be a container name, service name, or network alias resolvable on that shared network.

## 6. Verify installation files and permissions

```bash
cd "${POLLER_DIR}"

for file in \
  .env \
  compose.yaml \
  secrets/cato_api_key \
  secrets/cribl_ca.pem
 do
  test -e "${file}" || echo "MISSING: ${file}"
done

stat -c 'uid=%u gid=%g mode=%a size=%s path=%n' \
  .env \
  secrets/cato_api_key \
  secrets/cribl_ca.pem \
  state
```

Expected:

- `.env`: mode `600`
- API key file: UID/GID `10001`, mode `400`, non-empty
- CA file: UID/GID `10001`, mode `400`
- State directory: UID/GID `10001`, mode `700`

Repair without printing secrets:

```bash
chown 10001:10001 secrets/cato_api_key secrets/cribl_ca.pem state
chmod 0400 secrets/cato_api_key secrets/cribl_ca.pem
chmod 0700 state
chmod 0600 .env

if test -e state/marker.txt; then
  chown 10001:10001 state/marker.txt
  chmod 0600 state/marker.txt
fi
```

Do not make the key world-readable to resolve a permissions problem.

## 7. Verify the Cato endpoint and account ID

```bash
cd "${POLLER_DIR}"
grep -E '^(CATO_API_URL|CATO_ACCOUNT_ID)=' .env
```

The API URL must use the endpoint assigned to the test tenant, for example:

```text
https://api.us1.catonetworks.com/api/v1/graphql2
```

The account ID must be numeric, not the display name.

Test DNS and TLS to the endpoint:

```bash
CATO_HOST="$(sed -n 's#^CATO_API_URL=https://\([^/]*\)/.*#\1#p' .env)"
printf 'Cato host: %s\n' "${CATO_HOST}"
getent ahosts "${CATO_HOST}"

openssl s_client \
  -connect "${CATO_HOST}:443" \
  -servername "${CATO_HOST}" \
  </dev/null
```

Resolve DNS, routing, proxy, clock, certificate, or TLS-inspection problems before troubleshooting API permissions.

## 8. Run the installed Cato preflight

This calls the installed poller code, fetches one EventsFeed page into memory, does not send it to Cribl, and does not update the marker.

```bash
cd "${POLLER_DIR}"

docker compose run \
  --rm \
  --no-deps \
  --entrypoint python \
  cato-events-poller \
  -c '
import poller

marker = poller.read_marker()
result = poller.fetch(marker)
events = poller.extract_events(result)
fetched = int(result.get("fetchedCount") or 0)
returned_marker = result.get("marker") or ""

if fetched != len(events):
    raise SystemExit(
        f"Fetched/decoded mismatch: fetched={fetched}, decoded={len(events)}"
    )

print(
    "CATO API PREFLIGHT PASS "
    f"fetched={fetched} "
    f"decoded={len(events)} "
    f"current_marker_len={len(marker)} "
    f"returned_marker_len={len(returned_marker)}"
)
'
```

Expected:

```text
CATO API PREFLIGHT PASS fetched=N decoded=N current_marker_len=N returned_marker_len=N
```

### HTTP 401

Likely causes:

- Incorrect, truncated, expired, exposed, or revoked key
- Empty secret file
- Extra characters copied with the key

Check without displaying the key:

```bash
test -s secrets/cato_api_key && echo 'Key file is non-empty'
wc -c secrets/cato_api_key
```

### HTTP 403

Likely causes:

- Service principal lacks account or EventsFeed access
- Viewer scope is too narrow
- Allowed source-IP restriction excludes the host's public egress IP
- Service principal is disabled
- Key belongs to another account

### HTTP 404

Likely causes:

- Wrong regional hostname
- Missing `/api/v1/graphql2`
- Proxy or security device rewriting the request

### HTTP 422

Likely causes:

- Invalid account ID
- Schema or query validation failure
- Account is not accessible to the key

### HTTP 429

Stop duplicate pollers and reduce the polling frequency.

## 9. Run the Cribl connection preflight

```bash
cd "${POLLER_DIR}"

docker compose run \
  --rm \
  --no-deps \
  --entrypoint python \
  cato-events-poller \
  -c '
import poller

with poller.open_syslog_socket() as connection:
    peer = connection.getpeername()

print(
    "CRIBL CONNECTION PREFLIGHT PASS "
    f"host={poller.SYSLOG_HOST} "
    f"port={poller.SYSLOG_PORT} "
    f"tls={poller.SYSLOG_TLS} "
    f"peer={peer}"
)
'
```

### Name resolution failure

- Shared-network model: the containers are not on the same network or the configured name is not an alias.
- Published-port model: the Docker container cannot resolve the host DNS name.

### Connection refused

- Cribl Source is disabled.
- Wrong port.
- Source listens on UDP only.
- Docker does not publish the TCP port.
- Listener is bound only to localhost inside Cribl.

### Connection timeout

- Firewall drop.
- Wrong address.
- Docker routing or network ACL issue.
- Load balancer or VIP problem.

### TLS certificate error

Check:

- Cribl TLS is enabled on the selected port.
- `CRIBL_SYSLOG_TLS=true`.
- `CRIBL_SYSLOG_SERVER_NAME` matches a certificate SAN.
- The copied CA chain is correct.
- The certificate is current.
- Cribl is not requiring a client certificate; the demonstration poller does not present one.

## 10. Confirm the Cribl Syslog Source

In the test Worker Group or single instance, verify:

- Source type is Syslog.
- Protocol is TCP or TCP with TLS.
- Port matches the poller configuration.
- Source is enabled.
- Configuration is saved, committed, and deployed.
- Listener is reachable from the poller.
- Route and Destination are isolated for testing.

## 11. Send a synthetic event

Use the installed poller code so the event uses the same socket and RFC 5424 formatter as the real poller:

```bash
cd "${POLLER_DIR}"

docker compose run \
  --rm \
  --no-deps \
  --entrypoint python \
  cato-events-poller \
  -c '
import time
import poller

event = {
    "time": int(time.time() * 1000),
    "event_type": "Catocribbler Installer Synthetic Test",
    "vendor": "cato",
    "product": "cato_sase",
    "installer_test": True,
}

with poller.open_syslog_socket() as connection:
    connection.sendall(poller.syslog_line(event))

print("SYNTHETIC CRIBL EVENT SENT")
'
```

Confirm in Cribl:

1. Source receives the event.
2. `appname` is `cato-events`.
3. Route `cato_events_route` matches.
4. Pipeline `cato_normalize` runs.
5. `event_type` is `Catocribbler Installer Synthetic Test`.
6. Isolated test Destination receives the event.

## 12. Route and Pipeline failures

The supplied Route filter is:

```javascript
__inputId.startsWith('syslog:') && appname === 'cato-events'
```

If the Source receives the event but the Route does not match, check:

- `appname` value
- `__inputId`
- Route order
- Earlier final routes
- Whether the correct Worker Group received the committed configuration

If the Route matches but parsing fails, inspect:

```text
cato_parse_error
cribl_pipeline=cato_normalize_parse_failed
```

Confirm that the syslog `message` field contains one complete JSON object.

If the Pipeline succeeds but the Destination receives nothing, check:

- Route output ID
- Destination health and credentials
- Backpressure and persistent queues
- Destination-side filters
- Storage and license capacity

## 13. Continuous polling and marker problems

Start:

```bash
cd "${POLLER_DIR}"
docker compose up -d
docker compose logs -f cato-events-poller
```

A new installation begins with an empty marker and may immediately drain retained events in 3,000-record pages.

Successful logs resemble:

```text
INFO starting marker_len=0
INFO Fetched=3000 Sent=3000 marker_len=180
INFO Fetched=425 Sent=425 marker_len=180
```

`Fetched=0 Sent=0` is a successful poll with no new events.

Check marker metadata:

```bash
ls -l state/marker.txt
wc -c state/marker.txt
```

If no marker is created:

- No page may have been successfully delivered.
- State directory permissions may be wrong.
- Cribl connection may fail during the page.
- The API may return no new marker.

Do not create, edit, or copy a marker value manually.

## 14. Safe diagnostic collection

```bash
cd "${POLLER_DIR}"

printf '\n=== Git ===\n'
git -C "${INSTALL_DIR}" rev-parse HEAD
git -C "${INSTALL_DIR}" status --short

printf '\n=== Installation metadata ===\n'
cat "${INSTALL_DIR}/INSTALLATION_INFO.txt" 2>/dev/null || true

printf '\n=== Compose ===\n'
docker compose config --services
docker compose ps

printf '\n=== Logs ===\n'
docker compose logs --tail=200 cato-events-poller

printf '\n=== Permissions ===\n'
stat -c 'uid=%u gid=%g mode=%a size=%s path=%n' \
  .env \
  secrets/cato_api_key \
  secrets/cribl_ca.pem \
  state \
  state/marker.txt 2>/dev/null || true

printf '\n=== Cribl containers ===\n'
docker ps \
  --filter 'name=cribl' \
  --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
```

Redact before sharing:

- Account IDs
- Internal hostnames and addresses
- Event payloads
- API response bodies containing tenant context
- Marker values
- Certificates
- API keys

There is no official support recipient for these diagnostics.

## 15. Remove a failed demonstration

```bash
cd "${POLLER_DIR}"
docker compose down
```

Then revoke the Cato key, remove the demonstration service principal when appropriate, detach external Docker networks, and remove the selected installation directory only after preserving any approved evidence or state.

## No support, license, warranty, or liability

No person or organization is obligated to troubleshoot this code. Cato Networks and Cribl support organizations are not responsible for it. The repository contains no license grant from the author. All material is provided “AS IS” and “AS AVAILABLE.” Read [`../DISCLAIMER.md`](../DISCLAIMER.md).
