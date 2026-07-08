# Troubleshooting Cato EventsFeed to an existing Cribl Docker deployment

This project assumes that **Cribl Stream is already running in Docker** and that the customer is adding the `cato-events-poller` container beside it.

The poller does not install, upgrade, replace, or manage the existing Cribl deployment. It only:

1. Authenticates to the Cato GraphQL API.
2. Retrieves EventsFeed records for one Cato account.
3. Sends those records to an existing Cribl Syslog Source over TCP or TLS.

Troubleshoot the integration in that order. Do not begin by changing Cribl routes when the API key cannot authenticate, and do not regenerate Cato keys when the real problem is that two Docker networks cannot see each other. Humans already invented enough unnecessary variables.

## 1. Fast triage flow

Use this sequence:

1. Confirm the poller container starts.
2. Confirm the Cato API key and account ID authenticate directly to the configured Cato endpoint.
3. Confirm the poller container can open a TCP connection to the existing Cribl listener.
4. Confirm the Cribl Syslog Source is enabled, listening, and deployed.
5. Confirm the Cribl Route matches `appname === 'cato-events'`.
6. Confirm the `cato_normalize` Pipeline runs.
7. Confirm the selected Cribl Destination receives events.

The first failing step identifies the layer to fix.

## 2. Confirm the existing Cribl Docker environment

Before changing anything, identify the running Cribl containers, published ports, and Docker networks.

```bash
docker ps \
  --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
```

Identify the Cribl Worker or single-instance container that will receive syslog. The Leader management container is normally not the syslog target in a distributed deployment.

Inspect the selected Cribl container:

```bash
CRIBL_CONTAINER=cribl-worker

docker inspect "$CRIBL_CONTAINER" \
  --format 'Name={{.Name}}
Image={{.Config.Image}}
Networks={{json .NetworkSettings.Networks}}
PublishedPorts={{json .NetworkSettings.Ports}}'
```

Check Docker's published-port view:

```bash
docker port "$CRIBL_CONTAINER"
```

Typical published output might include:

```text
9514/tcp -> 0.0.0.0:9514
```

If no TCP port is published for the Syslog Source, the poller cannot reach it through the Docker host unless both containers share a Docker network.

## 3. Choose the Docker connectivity model

There are two supported approaches.

### Model A: Connect through a port published on the Docker host

Use this when the existing Cribl container publishes the Syslog TCP port, for example:

```text
0.0.0.0:9514->9514/tcp
```

Set:

```dotenv
CRIBL_SYSLOG_HOST=<docker-host-lan-ip-or-dns-name>
CRIBL_SYSLOG_PORT=9514
```

Do not use `127.0.0.1` or `localhost` in the poller container. Inside the poller, those addresses refer to the poller container itself, not the Docker host and not the Cribl container.

Confirm the host is listening:

```bash
ss -lnt | grep ':9514 '
```

Then test from the poller container using the TCP preflight in this document.

### Model B: Put the poller on the existing Cribl Docker network

Use this when the customer prefers container-to-container communication without publishing the syslog port externally.

Discover the Cribl network name:

```bash
docker inspect cribl-worker \
  --format '{{range $name, $_ := .NetworkSettings.Networks}}{{$name}}{{"\n"}}{{end}}'
```

Create `poller/compose.override.yaml`:

```yaml
services:
  cato-events-poller:
    networks:
      - cribl_existing

networks:
  cribl_existing:
    external: true
    name: <actual-cribl-docker-network-name>
```

Then set `CRIBL_SYSLOG_HOST` to the Cribl container name, Compose service name, or another DNS alias that resolves on that shared Docker network:

```dotenv
CRIBL_SYSLOG_HOST=cribl-worker
CRIBL_SYSLOG_PORT=9514
```

Validate name resolution from the poller image:

```bash
cd /opt/catocribbler/poller

docker compose run \
  --rm \
  --no-deps \
  --entrypoint python \
  cato-events-poller \
  -c '
import os
import socket

host = os.environ["CRIBL_SYSLOG_HOST"]
print(host, socket.getaddrinfo(host, None))
'
```

If the name does not resolve, the containers are not on the same user-defined Docker network or the selected name is not a network alias.

## 4. Create the correct Cato API key

Cato currently provides two API-key models.

### Admin API Key

An Admin API Key is tied to the individual Cato Management Application administrator who creates it. It is useful for personal testing and administrator-owned workflows.

To create one:

1. Sign in to the Cato Management Application.
2. Go to **Resources > Admin API Keys**.
3. Select **New**.
4. Enter a descriptive name such as `cribl-eventsfeed-test`.
5. Select **Downgrade to View** because this integration performs read-only query operations.
6. Optionally restrict **Allow access from IPs** to the Docker host's public egress IP address or approved range.
7. Set an expiration date according to policy.
8. Select **Apply**.
9. Copy the key immediately and store it securely. Cato does not show the value again after the creation dialog closes.

An Admin API Key inherits the administrator's RBAC permissions. If that administrator is disabled or deleted, the key stops working.

### Service API Key, recommended for production

A long-running container integration should normally use a Service API Key associated with a service principal rather than a human administrator.

Create the service principal:

1. Go to **Account > Administrators**.
2. Select **New**.
3. Select **Create New** and **Create as Service Principal**.
4. Enter a descriptive name such as `Cribl EventsFeed Poller`.
5. Assign the minimum role and scope required to query EventsFeed for the intended account.
6. Apply the configuration.

Create the key:

1. Go to **Resources > Service API Keys**.
2. Select **New**.
3. Select the service principal.
4. Enter a descriptive key name.
5. Select **Downgrade to View** for this read-only integration.
6. Optionally restrict allowed source IP addresses.
7. Set an expiration date according to policy.
8. Apply the configuration.
9. Copy the key immediately and store it securely.

The poller authenticates by sending the key in the HTTP header:

```text
x-api-key: <api-key>
```

## 5. Verify the Cato API URL and account ID

Required values:

```dotenv
CATO_API_URL=https://api.<tenant-region>.catonetworks.com/api/v1/graphql2
CATO_ACCOUNT_ID=<numeric-account-id>
```

The account ID is numeric and is not the tenant display name.

Do not guess the regional API hostname from geography. Use the endpoint assigned to the tenant or reuse an endpoint from a known-working Cato integration.

Examples that may be valid depending on the tenant:

```text
https://api.us1.catonetworks.com/api/v1/graphql2
https://api.catonetworks.com/api/v1/graphql2
```

## 6. Test DNS and TLS to the Cato endpoint

Extract the hostname from `.env`:

```bash
cd /opt/catocribbler/poller
CATO_HOST="$(sed -n 's#^CATO_API_URL=https://\([^/]*\)/.*#\1#p' .env)"
printf 'Cato host: %s\n' "$CATO_HOST"
```

Test DNS:

```bash
getent ahosts "$CATO_HOST"
```

Test TCP and TLS:

```bash
openssl s_client \
  -connect "${CATO_HOST}:443" \
  -servername "$CATO_HOST" \
  </dev/null
```

A DNS failure, TCP timeout, proxy block, or certificate error must be fixed before API-key troubleshooting is meaningful.

## 7. Authenticate directly to the Cato API endpoint

This direct test uses the configured endpoint and account ID, sends a minimal EventsFeed query, and prints only status and error information. It does not update the local marker or send records to Cribl.

Run from the Docker host:

```bash
cd /opt/catocribbler/poller

set -a
. ./.env
set +a

read -rsp 'Cato API key: ' CATO_API_KEY
export CATO_API_KEY
printf '\n'

python3 - <<'PY'
import json
import os
import urllib.error
import urllib.request

url = os.environ['CATO_API_URL']
account_id = os.environ['CATO_ACCOUNT_ID']
api_key = os.environ['CATO_API_KEY']

query = '''
query eventsFeed($accountIDs: [ID!]) {
  eventsFeed(accountIDs: $accountIDs) {
    marker
    fetchedCount
    accounts {
      id
      errorString
    }
  }
}
'''

body = json.dumps({
    'query': query,
    'variables': {'accountIDs': [account_id]},
}).encode('utf-8')

request = urllib.request.Request(
    url,
    data=body,
    headers={
        'Content-Type': 'application/json',
        'x-api-key': api_key,
        'User-Agent': 'catocribbler-auth-test',
    },
    method='POST',
)

try:
    with urllib.request.urlopen(request, timeout=30) as response:
        payload = json.loads(response.read().decode('utf-8'))
        print(f'HTTP status: {response.status}')
        if payload.get('errors'):
            print('GraphQL errors:')
            print(json.dumps(payload['errors'], indent=2))
            raise SystemExit(1)

        result = payload['data']['eventsFeed']
        print(f"Fetched count: {result.get('fetchedCount')}")
        account_errors = [
            account.get('errorString')
            for account in result.get('accounts') or []
            if account.get('errorString')
        ]
        if account_errors:
            print('Account errors:')
            print(json.dumps(account_errors, indent=2))
            raise SystemExit(1)

        print('CATO API AUTHENTICATION PASS')
except urllib.error.HTTPError as error:
    print(f'HTTP status: {error.code}')
    print(error.read().decode('utf-8', 'replace')[:4000])
    raise
PY

unset CATO_API_KEY
```

Expected result:

```text
HTTP status: 200
Fetched count: <number>
CATO API AUTHENTICATION PASS
```

## 8. Interpret Cato authentication failures

### HTTP 401

Common causes:

- Key value is incorrect, truncated, expired, or revoked.
- A newline or extra character was written into the key file.
- The `x-api-key` header is missing.

Check the local key file without printing it:

```bash
wc -c secrets/cato_api_key
od -An -t x1 secrets/cato_api_key | tail -n 1
```

Regenerate the key if there is any doubt. Do not paste it into tickets or chat.

### HTTP 403

Common causes:

- The key lacks permission for the account or EventsFeed query.
- The key's source-IP restriction excludes the Docker host's public egress IP.
- The key belongs to a different Cato account.
- The associated admin or service principal was disabled.

Confirm the host's public egress IP using the customer's approved network method and compare it with the Cato key's allowed-IP setting.

### HTTP 404

Common causes:

- Incorrect hostname.
- Missing `/api/v1/graphql2` path.
- Wrong regional endpoint.
- HTTP proxy or security service rewriting the request.

### HTTP 422

Common causes:

- Malformed GraphQL query.
- Invalid account-ID value.
- API schema mismatch.
- Request variables rejected by the selected endpoint.

Read the response body. It usually contains the specific GraphQL validation error.

### HTTP 429

The API is rate-limiting the client. Reduce parallel pollers, avoid multiple integrations polling the same tenant unnecessarily, and honor the retry interval.

### TLS verification error

Check:

- Host system date and time.
- Enterprise TLS inspection.
- Trusted CA bundle.
- Correct regional hostname.
- Proxy environment variables.

## 9. Run the poller's non-destructive Cato preflight

After the direct test passes, validate the actual container configuration:

```bash
cd /opt/catocribbler/poller

docker compose build --pull

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

print(
    "CATO API PREFLIGHT PASS "
    f"fetched={fetched} "
    f"decoded={len(events)} "
    f"current_marker_len={len(marker)} "
    f"returned_marker_len={len(returned_marker)}"
)

if fetched != len(events):
    raise SystemExit(
        f"Fetched/decoded mismatch: fetched={fetched}, decoded={len(events)}"
    )
'
```

If the direct host test passes but this container test fails, compare:

- `.env` values
- mounted key-file ownership and permissions
- container DNS and proxy settings
- Docker egress policy

## 10. Confirm the Cribl Syslog Source in the existing environment

In Cribl Stream, open the Worker Group or single instance that receives data.

Confirm the Syslog Source:

- Is enabled.
- Listens on TCP, not only UDP.
- Uses the expected port, commonly `9514`.
- Listens on `0.0.0.0` or another address reachable in the container.
- Has TLS enabled only when the poller is configured for TLS.
- Has been saved, committed, and deployed to the active Worker Group.

Current Cribl versions include a preconfigured Syslog Source on port `9514`, but it still must be enabled and deployed before it receives traffic.

## 11. Test TCP connectivity from the poller container

```bash
cd /opt/catocribbler/poller

docker compose run \
  --rm \
  --no-deps \
  --entrypoint python \
  cato-events-poller \
  -c '
import os
import socket

host = os.environ["CRIBL_SYSLOG_HOST"]
port = int(os.environ.get("CRIBL_SYSLOG_PORT", "9514"))

addresses = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
print(f"Resolved addresses: {addresses}")

with socket.create_connection((host, port), timeout=5):
    print(f"CRIBL TCP PREFLIGHT PASS host={host} port={port}")
'
```

### Name resolution failure

- Shared-network model: containers are not attached to the same Docker network or the hostname is not a valid network alias.
- Host-published-port model: the configured host DNS name does not resolve inside Docker.

### Connection refused

- Cribl Source is disabled.
- Wrong TCP port.
- Docker did not publish the port.
- Cribl is listening only on localhost inside its container.
- The listener is configured for UDP only.

### Connection timeout

- Firewall drop.
- Wrong IP address.
- Docker routing problem.
- Load balancer or network ACL issue.

## 12. Test Cribl TLS from the poller container

For a TLS listener:

```bash
cd /opt/catocribbler/poller

docker compose run \
  --rm \
  --no-deps \
  --entrypoint python \
  cato-events-poller \
  -c '
import os
import socket
import ssl

host = os.environ["CRIBL_SYSLOG_HOST"]
port = int(os.environ.get("CRIBL_SYSLOG_PORT", "9514"))
server_name = os.environ.get("CRIBL_SYSLOG_SERVER_NAME", host)
ca_file = os.environ.get("CRIBL_SYSLOG_CA_FILE")

context = ssl.create_default_context(cafile=ca_file or None)
with socket.create_connection((host, port), timeout=5) as raw:
    with context.wrap_socket(raw, server_hostname=server_name) as tls:
        print(f"TLS version: {tls.version()}")
        print(f"Peer: {tls.getpeercert().get('subjectAltName')}")
        print("CRIBL TLS PREFLIGHT PASS")
'
```

If this fails:

- Confirm Cribl TLS is enabled on that exact TCP port.
- Confirm the CA chain in `secrets/cribl_ca.pem` validates the Cribl certificate.
- Confirm `CRIBL_SYSLOG_SERVER_NAME` matches a certificate SAN.
- Confirm no middlebox is replacing the certificate.

## 13. Send a synthetic event to the existing Cribl source

This validates Cribl without calling Cato.

Plain TCP example:

```bash
printf '<134>1 2026-01-01T00:00:00.000Z test-host cato-events - - - {"time":1767225600000,"event_type":"Synthetic Test","vendor":"cato","product":"cato_sase"}\n' \
  | nc <cribl-host> 9514
```

Then confirm in Cribl that the event:

- Appears at the Syslog Source.
- Has `appname=cato-events`.
- Matches the Cato Route.
- Passes through `cato_normalize`.
- Reaches the selected Destination.

If the source receives the event but the route does not match, inspect the actual `__inputId` and route order.

## 14. Route compatibility with an existing Cribl source

The repository Route matches any Cribl Syslog Source when the RFC 5424 application name is `cato-events`:

```javascript
__inputId.startsWith('syslog:') && appname === 'cato-events'
```

This avoids assuming the customer's existing Source ID is exactly `in_syslog` or `in_syslog_default`.

Place the Cato Route above broad catch-all routes that might consume the same syslog event first.

## 15. Poller log interpretation

### Healthy

```text
INFO starting marker_len=180
INFO Fetched=144 Sent=144 marker_len=180
```

### Healthy with no new events

```text
INFO Fetched=0 Sent=0 marker_len=180
```

### Cato works, Cribl connection fails

Typical traceback includes:

```text
ConnectionRefusedError
TimeoutError
socket.gaierror
ssl.SSLCertVerificationError
```

Fix Docker networking, listener configuration, or TLS.

### Cato authentication fails

Typical traceback includes:

```text
Cato API HTTP 401
Cato API HTTP 403
Cato API HTTP 422
```

Use the direct authentication test and inspect the response body.

### `Fetched` and `Sent` do not match

The page should be treated as failed. The marker should not advance. Review the full traceback and Cribl connection state.

## 16. Secret-file and state permissions

The container runs as UID `10001`.

Check:

```bash
cd /opt/catocribbler/poller

stat -c 'uid=%u gid=%g mode=%a path=%n' \
  secrets/cato_api_key \
  secrets/cribl_ca.pem \
  state
```

Recommended values:

- API key file: owner UID `10001`, mode `400`
- CA file: owner UID `10001`, mode `400`
- State directory: owner UID `10001`, mode `700`

Repair:

```bash
chown 10001 secrets/cato_api_key secrets/cribl_ca.pem state
chmod 0400 secrets/cato_api_key secrets/cribl_ca.pem
chmod 0700 state

if test -e state/marker.txt; then
  chown 10001 state/marker.txt
  chmod 0600 state/marker.txt
fi
```

The state directory must be writable because marker updates use atomic file replacement.

## 17. Verify the running poller and marker

```bash
cd /opt/catocribbler/poller

docker compose ps
docker compose logs --tail=100 cato-events-poller
ls -l state/marker.txt
wc -c state/marker.txt
```

The marker length is not guaranteed to be 180 bytes. It is opaque and must not be edited manually.

## 18. Distinguish socket delivery from Cribl destination delivery

A log line such as:

```text
Fetched=144 Sent=144
```

means the poller wrote 144 syslog records successfully to the connected TCP socket. It does not by itself prove that:

- The Cribl Route matched.
- The Pipeline parsed the payload.
- The downstream Destination accepted the event.
- A destination persistent queue is healthy.

Confirm each stage in Cribl metrics, Live Capture, Route preview, Pipeline preview, and Destination metrics.

## 19. Collect safe diagnostics

These commands avoid printing the API key or full marker:

```bash
cd /opt/catocribbler/poller

printf '\n=== Git ===\n'
git rev-parse HEAD
git status --short

printf '\n=== Compose ===\n'
docker compose config --services
docker compose ps

printf '\n=== Poller logs ===\n'
docker compose logs --tail=200 cato-events-poller

printf '\n=== Permissions ===\n'
stat -c 'uid=%u gid=%g mode=%a path=%n' \
  .env secrets secrets/cato_api_key secrets/cribl_ca.pem state \
  state/marker.txt 2>/dev/null || true

printf '\n=== Marker metadata ===\n'
wc -c state/marker.txt 2>/dev/null || true
sha256sum state/marker.txt 2>/dev/null || true

printf '\n=== Existing Cribl containers ===\n'
docker ps \
  --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' \
  | grep -E 'NAMES|cribl' || true
```

Before sharing diagnostics, redact:

- Account IDs
- Internal hostnames and IP addresses
- Event payloads
- API error bodies containing tenant details
- Marker values
- Certificates
- API keys

## 20. Known-good end-to-end state

The integration is healthy when all of the following are true:

- Direct Cato authentication test passes.
- Container Cato preflight passes.
- Poller-to-Cribl TCP or TLS preflight passes.
- Existing Cribl Syslog Source receives the synthetic test.
- Cato Route matches `appname=cato-events`.
- `cato_normalize` promotes JSON fields.
- Destination metrics increase.
- Poller logs repeatedly show matching `Fetched` and `Sent` counts.
- Marker file exists and changes over time when new events arrive.
