# Troubleshooting the unsupported Cato-to-Cribl demonstration

> [!CAUTION]
> **UNSUPPORTED, NON-PRODUCTION DEMONSTRATION ONLY.** This material is not a support service, supported runbook, official integration guide, or assurance that the code can be made safe or reliable. Damon Cassell, Cato Networks, Cribl, employers, contributors, vendors, partners, and all other parties provide no support, warranty, maintenance, incident response, or obligation to help. There is no license grant. Read [`../DISCLAIMER.md`](../DISCLAIMER.md).

The default installation directory is `/opt/cribbler`, but the installer allows another absolute path.

```bash
INSTALL_DIR=${INSTALL_DIR:-/opt/cribbler}
POLLER_DIR="${INSTALL_DIR}/poller"
```

## 1. Troubleshooting order

Use this sequence:

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

The first failing layer identifies where to investigate. Rotating credentials does not repair Docker networking, despite the ancient administrative ritual suggesting otherwise.

## 2. Current defaults

| Setting | Default |
|---|---|
| Cato GraphQL API URL | `https://api.catonetworks.com/api/v1/graphql` |
| Cribl connection method | Published host TCP port |
| Cribl Syslog port | `9514` |
| Cribl TLS | Disabled |
| Poll interval | 30 seconds |

## 3. Installer failures

### `An interactive terminal is required`

The installer reads prompts from `/dev/tty` so it remains interactive through a pipe.

Run from an interactive SSH or console session:

```bash
test -r /dev/tty && test -w /dev/tty && echo 'TTY PASS'
```

### `Run this installer as root`

Use:

```bash
sudo bash /tmp/catocribbler-install.sh
```

### Missing required commands

```bash
git --version
docker version
docker compose version
python3 --version
```

Docker Compose v2 through `docker compose` is required.

### Installation directory already exists and is not empty

The installer refuses to overwrite an existing installation.

```bash
ls -la /opt/cribbler
```

Choose another empty directory or remove the old demonstration only after preserving approved marker state and revoking old credentials.

### Installer stopped after cloning or building

```bash
cd "${INSTALL_DIR}"
git status --short
git rev-parse HEAD

cd poller
docker compose config
docker compose ps -a
docker compose logs --tail=100 2>/dev/null || true
```

## 4. Choosing the Cribl connection method

### Option 1: Published host TCP port, recommended default

Use this when the Cribl container publishes the Syslog Source port to the Docker host:

```text
0.0.0.0:9514->9514/tcp
```

Configure the Docker host's LAN IP address or DNS name.

Advantages:

- Simpler to troubleshoot
- No shared Docker network membership
- No dependence on local network names or aliases
- More portable between customer environments

Do not use `localhost` or `127.0.0.1`; inside the poller container those addresses refer to the poller itself.

Confirm the published port:

```bash
docker ps \
  --filter 'name=cribl' \
  --format 'table {{.Names}}\t{{.Ports}}'

ss -lnt | grep ':9514 '
```

### Option 2: Shared external Docker network, advanced fallback

Use this when the Syslog TCP port is not published or direct container-to-container networking is required.

The poller joins an existing Cribl Docker network and connects using a container, service, or network-alias name.

Check networks:

```bash
docker network ls

docker inspect cribl-worker \
  --format '{{json .NetworkSettings.Networks}}'
```

Inspect the generated override:

```bash
cat "${POLLER_DIR}/compose.override.yaml"
```

This option gives the poller access to other services exposed on the selected network. Use only an isolated non-production network.

**Recommendation:** use option 1 unless the Cribl listener is not published or the deployment specifically requires option 2.

## 5. Verify installation files and permissions

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
  secrets \
  secrets/cato_api_key \
  secrets/cribl_ca.pem \
  state
```

Expected:

- `.env`: mode `600`
- Secret directory: UID/GID `10001`, mode `700`
- API key: UID/GID `10001`, mode `400`, non-empty
- CA file: UID/GID `10001`, mode `400`
- State directory: UID/GID `10001`, mode `700`

Repair:

```bash
chown 10001:10001 \
  secrets \
  secrets/cato_api_key \
  secrets/cribl_ca.pem \
  state

chmod 0700 secrets state
chmod 0400 secrets/cato_api_key secrets/cribl_ca.pem
chmod 0600 .env

if test -e state/marker.txt; then
  chown 10001:10001 state/marker.txt
  chmod 0600 state/marker.txt
fi
```

Do not make the key world-readable.

## 6. Verify the Cato endpoint and account ID

```bash
cd "${POLLER_DIR}"
grep -E '^(CATO_API_URL|CATO_ACCOUNT_ID)=' .env
```

Expected default endpoint:

```text
https://api.catonetworks.com/api/v1/graphql
```

The account ID must be numeric.

Test DNS and TLS:

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

## 7. Run the installed Cato preflight

This fetches and decodes one EventsFeed page without sending records to Cribl or writing the marker.

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
- Extra copied characters

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

- Incorrect endpoint path
- Proxy or security device rewriting the request

### HTTP 422

Likely causes:

- Invalid account ID
- Schema or query validation failure
- Account is not accessible to the key

### HTTP 429

Stop duplicate pollers and reduce polling frequency.

## 8. Run the Cribl connection preflight

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

- Published-port model: the container cannot resolve the Docker host DNS name.
- Shared-network model: the containers are not on the same network or the configured name is not a valid alias.

### Connection refused

- Cribl Source is disabled.
- Wrong port.
- Source listens on UDP only.
- Docker does not publish the TCP port.
- Listener is bound incorrectly.

### Connection timeout

- Firewall drop.
- Wrong address.
- Docker routing or network ACL problem.
- Load balancer or VIP problem.

### TLS certificate error

Check:

- TLS is enabled on the selected Cribl Source port.
- `CRIBL_SYSLOG_TLS=true`.
- `CRIBL_SYSLOG_SERVER_NAME` matches a certificate SAN.
- The CA chain is correct.
- The certificate is current.
- Cribl is not requiring a client certificate; the poller does not present one.

## 9. Send a synthetic event

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
5. The isolated test Destination receives the event.

## 10. Route, Pipeline, and Destination failures

The supplied Route filter is:

```javascript
__inputId.startsWith('syslog:') && appname === 'cato-events'
```

If the Source receives the event but the Route does not match, check:

- `appname`
- `__inputId`
- Route order
- Earlier final routes
- Correct Worker Group deployment

If the Route matches but parsing fails, inspect:

```text
cato_parse_error
cribl_pipeline=cato_normalize_parse_failed
```

If the Pipeline succeeds but the Destination receives nothing, check:

- Route output ID
- Destination health and credentials
- Backpressure and queues
- Destination-side filters
- Storage and license capacity

## 11. Continuous polling and marker state

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

Inspect marker metadata without displaying the value:

```bash
ls -l state/marker.txt
wc -c state/marker.txt
```

Do not create, edit, or copy a marker manually.

## 12. Safe diagnostics

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
  secrets \
  secrets/cato_api_key \
  secrets/cribl_ca.pem \
  state \
  state/marker.txt 2>/dev/null || true
```

Redact account IDs, internal addresses, event payloads, marker values, certificates, and API keys before sharing.

## 13. Remove a failed demonstration

```bash
cd "${POLLER_DIR}"
docker compose down
```

Then revoke the Cato key, remove the demonstration service principal when appropriate, detach external Docker networks, and remove the selected installation directory only after preserving any approved evidence or state.

## No support, license, warranty, or liability

No person or organization is obligated to troubleshoot this code. Cato Networks and Cribl support organizations are not responsible for it. All material is provided “AS IS” and “AS AVAILABLE.” Read [`../DISCLAIMER.md`](../DISCLAIMER.md).
