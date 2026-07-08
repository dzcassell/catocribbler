# Troubleshooting the unsupported Cato-to-Cribl demonstration

> [!CAUTION]
> **UNSUPPORTED, NON-PRODUCTION DEMONSTRATION ONLY.** This troubleshooting material is not a support service, supported runbook, official integration guide, or assurance that the code can be made safe or reliable. Damon Cassell, Cato Networks, Cribl, employers, contributors, vendors, partners, and all other parties provide no support, warranty, maintenance, incident response, or obligation to help. There is no license grant from the author. Do not troubleshoot this code in production because it should not be there. Read [`../DISCLAIMER.md`](../DISCLAIMER.md).

This project assumes Cribl Stream is already running in Docker and an evaluator is adding `cato-events-poller` in an isolated, disposable, non-production environment.

The poller attempts to:

1. Authenticate to the Cato GraphQL API.
2. Retrieve EventsFeed records for one approved test account.
3. Send RFC 5424 records to an existing non-production Cribl Syslog Source.

Troubleshoot in that order. Do not rearrange Cribl routes when the Cato key cannot authenticate, and do not regenerate API keys when the real problem is that two Docker networks cannot see each other. Computers are literal enough without additional human improvisation.

## 1. Stop if the environment is production

Do not continue if any of the following are true:

- The Cato account contains production data and has not been explicitly approved for this test.
- The Cribl Worker Group, Source, Route table, Pipeline, or Destination is production.
- The downstream Destination triggers production alerting, automation, billing, retention, or compliance workflows.
- The Docker host or shared network is production.
- The test can expose API keys, certificates, event data, or internal network information.
- There is no rollback, cleanup, key-revocation, and data-destruction plan.

Move the demonstration to an isolated environment before proceeding.

## 2. Fast triage flow

Use this sequence:

1. Confirm the demonstration container can start.
2. Confirm the Cato key and account ID authenticate directly to the configured endpoint.
3. Confirm the poller container can resolve and connect to the test Cribl listener.
4. Confirm TLS when enabled.
5. Confirm the test Syslog Source is enabled and deployed.
6. Send a synthetic event.
7. Confirm the Route matches `appname === 'cato-events'`.
8. Confirm `cato_normalize` runs.
9. Confirm the isolated test Destination receives the event.
10. Start EventsFeed polling only after the preceding tests pass.

The first failing step identifies the layer to investigate. None of these checks establishes production readiness.

## 3. Inspect the existing non-production Cribl Docker environment

```bash
docker ps \
  --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
```

Identify the test Worker or single-instance container that receives data. A Leader management port is normally not the syslog target in a distributed deployment.

```bash
CRIBL_CONTAINER=cribl-worker

docker inspect "$CRIBL_CONTAINER" \
  --format 'Name={{.Name}}
Image={{.Config.Image}}
Networks={{json .NetworkSettings.Networks}}
PublishedPorts={{json .NetworkSettings.Ports}}'

docker port "$CRIBL_CONTAINER"
```

If no TCP port is published for the test Syslog Source, use a shared test Docker network or add an approved test-only mapping. Do not alter production Docker mappings for this demonstration.

## 4. Choose the Docker connectivity model

### Host-published test port

Use this when the test Cribl container publishes a mapping such as:

```text
0.0.0.0:9514->9514/tcp
```

Configure:

```dotenv
CRIBL_SYSLOG_HOST=<docker-test-host-ip-or-dns-name>
CRIBL_SYSLOG_PORT=9514
```

Do not use `127.0.0.1` or `localhost`; inside the poller container those addresses refer to the poller itself.

Confirm the test host is listening:

```bash
ss -lnt | grep ':9514 '
```

### Shared external test network

Discover the Cribl network:

```bash
docker inspect "$CRIBL_CONTAINER" \
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
    name: <actual-non-production-cribl-network-name>
```

Configure:

```dotenv
CRIBL_SYSLOG_HOST=cribl-worker
CRIBL_SYSLOG_PORT=9514
```

Attaching the poller to an external network grants access to whatever that network exposes. Do not attach it to production or unrelated networks.

## 5. Create a restricted Cato API key for testing

### Admin API Key

An Admin API Key is tied to the individual administrator who creates it.

For a controlled short test:

1. Go to **Resources > Admin API Keys**.
2. Select **New**.
3. Use a descriptive demonstration name.
4. Select **Downgrade to View**.
5. Restrict allowed source IPs where practical.
6. Set a short expiration.
7. Apply the configuration.
8. Copy the key immediately and store it securely.

The key can stop working if the administrator is disabled, deleted, or re-scoped.

### Service API Key

A Service API Key can avoid tying a shared test to a human account, but it does not make this code supported or production-ready.

Create a service principal under **Account > Administrators**, assign only the minimum test-account scope, then create the key under **Resources > Service API Keys** with view-only access, source-IP restrictions, and a short expiration.

Revoke the key and remove a demonstration-only principal when testing ends.

The poller sends:

```text
x-api-key: <api-key>
```

## 6. Verify the Cato endpoint and account ID

Required values:

```dotenv
CATO_API_URL=https://api.<tenant-region>.catonetworks.com/api/v1/graphql2
CATO_ACCOUNT_ID=<numeric-account-id>
```

The account ID is numeric and is not the display name.

Do not guess the regional endpoint. Examples that may apply to some tenants include:

```text
https://api.us1.catonetworks.com/api/v1/graphql2
https://api.catonetworks.com/api/v1/graphql2
```

Use only the endpoint assigned to the approved test account.

## 7. Test DNS and TLS to Cato

```bash
cd /opt/catocribbler/poller
CATO_HOST="$(sed -n 's#^CATO_API_URL=https://\([^/]*\)/.*#\1#p' .env)"
printf 'Cato host: %s\n' "$CATO_HOST"
getent ahosts "$CATO_HOST"
```

Test TLS:

```bash
openssl s_client \
  -connect "${CATO_HOST}:443" \
  -servername "$CATO_HOST" \
  </dev/null
```

Fix DNS, routing, proxy, TLS inspection, clock, or certificate problems before API-key troubleshooting.

## 8. Authenticate directly to the Cato API endpoint

This test queries Cato but does not send to Cribl or update the local marker. It can still retrieve sensitive account information into memory and terminal output. Use only the approved test account.

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
        'User-Agent': 'catocribbler-demonstration-auth-test',
    },
    method='POST',
)

try:
    with urllib.request.urlopen(request, timeout=30) as response:
        payload = json.loads(response.read().decode('utf-8'))
        print(f'HTTP status: {response.status}')
        if payload.get('errors'):
            print(json.dumps(payload['errors'], indent=2))
            raise SystemExit(1)

        result = payload['data']['eventsFeed']
        print(f"Fetched count: {result.get('fetchedCount')}")
        errors = [
            account.get('errorString')
            for account in result.get('accounts') or []
            if account.get('errorString')
        ]
        if errors:
            print(json.dumps(errors, indent=2))
            raise SystemExit(1)

        print('CATO API AUTHENTICATION PASS')
except urllib.error.HTTPError as error:
    print(f'HTTP status: {error.code}')
    print(error.read().decode('utf-8', 'replace')[:4000])
    raise
PY

unset CATO_API_KEY
```

Expected test result:

```text
HTTP status: 200
Fetched count: <number>
CATO API AUTHENTICATION PASS
```

## 9. Interpret Cato failures

### HTTP 401

Possible causes:

- Incorrect, truncated, expired, or revoked key.
- Extra newline or character in the key file.
- Missing `x-api-key` header.

Check without printing the key:

```bash
wc -c secrets/cato_api_key
od -An -t x1 secrets/cato_api_key | tail -n 1
```

### HTTP 403

Possible causes:

- Insufficient account or query permission.
- Source-IP restriction excludes the test host's public egress IP.
- Key belongs to another account.
- Associated administrator or service principal is disabled.

### HTTP 404

Possible causes:

- Incorrect hostname.
- Missing `/api/v1/graphql2`.
- Wrong regional endpoint.
- Proxy or security device rewriting the request.

### HTTP 422

Possible causes:

- Malformed GraphQL query.
- Invalid account ID.
- Schema mismatch.
- Variables rejected by the endpoint.

Review the response body carefully and redact it before sharing.

### HTTP 429

The API is rate-limiting the test. Stop duplicate pollers and reduce test frequency.

### TLS verification error

Check system time, CA trust, proxy settings, TLS inspection, and the regional hostname.

## 10. Run the demonstration container's Cato preflight

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

If the host test passes but this fails, compare `.env`, file permissions, container DNS, proxy variables, Docker egress policy, and CA trust.

## 11. Confirm the test Cribl Syslog Source

In the non-production Cribl Worker Group or single instance, confirm the Source:

- Is explicitly approved for the demonstration.
- Is enabled.
- Listens on TCP, not only UDP.
- Uses the expected test port.
- Listens on a reachable address.
- Has TLS enabled only when the poller uses TLS.
- Is saved, committed, and deployed.
- Routes only to an isolated test Destination.

## 12. Test TCP from the poller container

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

### Name-resolution failure

- Shared-network model: containers are not attached to the same test network or the name is not a valid alias.
- Host-port model: configured DNS does not resolve inside Docker.

### Connection refused

- Test Source disabled.
- Wrong TCP port.
- Port not published.
- Listener bound only to localhost inside Cribl.
- Source configured for UDP only.

### Connection timeout

- Firewall drop.
- Wrong address.
- Docker routing issue.
- Network ACL or load-balancer problem.

## 13. Test Cribl TLS

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

Check port, certificate SAN, CA chain, expiration, and whether the Source incorrectly requires a client certificate.

## 14. Send a synthetic test event

Plain TCP example:

```bash
printf '<134>1 2026-01-01T00:00:00.000Z test-host cato-events - - - {"time":1767225600000,"event_type":"Synthetic Test","vendor":"cato","product":"cato_sase"}\n' \
  | nc <cribl-test-host> 9514
```

Confirm:

- Test Source receives it.
- `appname=cato-events`.
- Demonstration Route matches.
- Demonstration Pipeline runs.
- Isolated test Destination receives it.

## 15. Route compatibility

The supplied demonstration filter is:

```javascript
__inputId.startsWith('syslog:') && appname === 'cato-events'
```

This avoids assuming a specific Source ID. It can still match unintended events if another sender uses the same `appname`. Review Route scope and order in the test environment.

## 16. Interpret poller logs

### Apparently successful socket write

```text
INFO Fetched=144 Sent=144 marker_len=180
```

This does not prove downstream delivery or correctness.

### No new test events

```text
INFO Fetched=0 Sent=0 marker_len=180
```

### Cato failure

Typical errors include:

```text
Cato API HTTP 401
Cato API HTTP 403
Cato API HTTP 422
```

### Network or TLS failure

Typical exceptions include:

```text
ConnectionRefusedError
TimeoutError
socket.gaierror
ssl.SSLCertVerificationError
```

## 17. Secret and state permissions

The container runs as UID `10001`.

```bash
cd /opt/catocribbler/poller

stat -c 'uid=%u gid=%g mode=%a path=%n' \
  secrets/cato_api_key \
  secrets/cribl_ca.pem \
  state
```

Suggested demonstration values:

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

## 18. Collect limited diagnostics

These commands avoid intentionally printing the API key or marker value, but output can still contain sensitive hostnames, addresses, tenant identifiers, and error details:

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

printf '\n=== Cribl containers ===\n'
docker ps \
  --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' \
  | grep -E 'NAMES|cribl' || true
```

Redact before sharing:

- Account IDs
- Internal hostnames and addresses
- Event payloads
- API error bodies containing tenant details
- Marker values
- Certificates
- API keys

There is no support recipient for these diagnostics. They are for the evaluator's own investigation.

## 19. End the test instead of escalating it into production

The demonstration is complete when the evaluator has observed the intended data flow in an isolated environment. It should then be removed, not promoted.

```bash
cd /opt/catocribbler/poller
docker compose down
```

Revoke the Cato key, remove demonstration Cribl objects, detach the external network, and destroy test secrets and data according to policy.

## No support, license, warranty, or liability

No person or organization is obligated to help troubleshoot this code. Cato Networks and Cribl support organizations are not responsible for it. Damon Cassell and repository contributors provide no support commitment.

The repository intentionally contains no license grant from the author. All material is provided “AS IS” and “AS AVAILABLE,” with no warranties and no liability to the maximum extent permitted by applicable law.

Read [`../DISCLAIMER.md`](../DISCLAIMER.md).
