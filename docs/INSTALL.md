# Install the Cato poller beside an existing Cribl Docker deployment

> [!CAUTION]
> **UNSUPPORTED, NON-PRODUCTION DEMONSTRATION ONLY.** This guide and the code it describes are not supported by Damon Cassell, Cato Networks, Cribl, any employer, contributor, vendor, partner, or anyone else. There is no license grant, no warranty, no maintenance commitment, and no obligation to help. Do not use this code in production. Read [`../DISCLAIMER.md`](../DISCLAIMER.md) before continuing.

This guide installs only the experimental `cato-events-poller` container.

It assumes Cribl Stream is already running in Docker and that an evaluator is adding this poller in an isolated, disposable, non-production environment using synthetic or specifically approved test data.

The procedure is:

1. Inspect the existing non-production Cribl deployment.
2. Create a short-lived, restricted Cato API key.
3. Validate Cato authentication independently.
4. Choose Docker networking between the demonstration poller and Cribl.
5. Configure the poller.
6. Test Cato and Cribl independently.
7. Start the demonstration.
8. Validate routing and test-destination delivery.
9. Remove the demonstration and revoke the key when testing ends.

Nothing in this guide is a recommendation, supported architecture, certification, or statement of production readiness.

## 1. Prerequisites

You need:

- An isolated Linux test host with Docker privileges.
- Docker Engine and Docker Compose v2.
- Git.
- An existing non-production Cribl Stream Docker deployment.
- Permission to modify the applicable Cribl test Worker Group or single instance.
- Cato administrative assistance to create a restricted, short-lived API key.
- Outbound HTTPS access to the correct Cato API endpoint.
- Network access from the poller container to the test Cribl Syslog Source.
- Approval to use the selected test tenant, account, events, and downstream Destination.
- A cleanup plan, key-revocation plan, and backup of any state that matters to the demonstration.

Verify local tools:

```bash
docker version
docker compose version
git --version
```

## 2. Inspect the existing Cribl containers

List running containers:

```bash
docker ps \
  --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
```

Identify the non-production data-processing container:

- Single-instance Cribl: the single Cribl container.
- Distributed Cribl: a Worker container, Worker load balancer, or VIP for the test Worker Group.
- Do not target the Leader management port unless that node is intentionally processing test data.

Set the selected container name:

```bash
CRIBL_CONTAINER=cribl-worker
```

Inspect its networks and published ports:

```bash
docker inspect "$CRIBL_CONTAINER" \
  --format 'Name={{.Name}}
Networks={{json .NetworkSettings.Networks}}
Ports={{json .NetworkSettings.Ports}}'

docker port "$CRIBL_CONTAINER"
```

Record:

- Cribl container or service name.
- Docker network name.
- Published Syslog TCP port, if any.
- Test Worker Group receiving the configuration.
- Isolated test Destination.

## 3. Choose how the poller reaches Cribl

### Option A: Existing Cribl container publishes the Syslog port

Example Docker port mapping:

```text
9514/tcp -> 0.0.0.0:9514
```

Use the Docker host's test-network IP or DNS name:

```dotenv
CRIBL_SYSLOG_HOST=192.0.2.25
CRIBL_SYSLOG_PORT=9514
```

Do not use `localhost` or `127.0.0.1` in `.env`. Inside the poller container, those addresses point to the poller itself.

### Option B: Attach the poller to the existing Cribl Docker network

Discover the network:

```bash
docker inspect "$CRIBL_CONTAINER" \
  --format '{{range $name, $_ := .NetworkSettings.Networks}}{{$name}}{{"\n"}}{{end}}'
```

After cloning the repository, create `poller/compose.override.yaml`:

```yaml
services:
  cato-events-poller:
    networks:
      - cribl_existing

networks:
  cribl_existing:
    external: true
    name: <actual-existing-cribl-network-name>
```

Use the Cribl service name, container name, or network alias:

```dotenv
CRIBL_SYSLOG_HOST=cribl-worker
CRIBL_SYSLOG_PORT=9514
```

Attaching a container to an existing Docker network increases its network access. Review that access and use only an isolated test network.

## 4. Confirm the existing Cribl Syslog Source

In Cribl Stream, open the single instance or target test Worker Group.

Confirm or create a Syslog Source with:

| Setting | Demonstration value |
|---|---|
| Protocol | TCP, or TCP with TLS |
| Address | `0.0.0.0` unless deliberately restricted |
| TCP port | Commonly `9514` |
| Enabled | Yes |
| Configuration state | Saved, committed, and deployed |
| Destination | Isolated test Destination only |

The supplied Route does not require a specific Source ID. It matches any Cribl Syslog Source when the RFC 5424 application name is `cato-events`.

See [`CRIBL.md`](CRIBL.md) for the complete demonstration Source, Route, Pipeline, and Destination procedure.

## 5. Collect the required Cato values

You need:

- `CATO_API_URL`
- `CATO_ACCOUNT_ID`
- A restricted, short-lived Cato API key

### Cato API URL

Use the endpoint assigned to the test tenant. Example:

```text
https://api.us1.catonetworks.com/api/v1/graphql2
```

Some tenants or examples may use:

```text
https://api.catonetworks.com/api/v1/graphql2
```

Do not guess the regional hostname.

### Cato account ID

Use the numeric account identifier, not the display name.

Example:

```text
12345
```

## 6. Create a Cato API key for the demonstration

Cato separates Admin API Keys from Service API Keys.

### Admin API Key

An Admin API Key can be used for a controlled, short-lived administrator test.

1. Go to **Resources > Admin API Keys**.
2. Select **New**.
3. Enter a descriptive name such as `cribl-eventsfeed-demo`.
4. Select **Downgrade to View** because this demonstration performs read-only queries.
5. Restrict allowed source IPs to the test host's public egress IP where practical.
6. Set a short expiration.
7. Apply the configuration.
8. Copy the key immediately and store it securely.

The key inherits the administrator's RBAC permissions and can stop working if the administrator is disabled, deleted, or re-scoped.

### Service API Key

A Service API Key can avoid tying a shared demonstration to a human administrator, but it does not make this code production-ready or supported.

Create a service principal:

1. Go to **Account > Administrators**.
2. Select **New**.
3. Select **Create New** and **Create as Service Principal**.
4. Enter a descriptive name such as `Cribl EventsFeed Demo`.
5. Assign the minimum test-account scope required for EventsFeed queries.
6. Apply the configuration.

Create the key:

1. Go to **Resources > Service API Keys**.
2. Select **New**.
3. Select the service principal.
4. Enter a descriptive name.
5. Select **Downgrade to View**.
6. Restrict allowed source IPs where practical.
7. Set a short expiration.
8. Apply the configuration.
9. Copy the key immediately and store it securely.

Revoke the key when the demonstration is complete.

The poller authenticates using:

```text
x-api-key: <api-key>
```

## 7. Authenticate directly to Cato before installing the poller

Use the direct API test in [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md#7-authenticate-directly-to-the-cato-api-endpoint).

Do not continue until the result is:

```text
CATO API AUTHENTICATION PASS
```

This isolates endpoint, account ID, RBAC, IP restrictions, and key validity before Docker and Cribl are added to the equation.

## 8. Clone the repository

Choose a protected test path:

```bash
sudo -i
cd /opt
git clone https://github.com/dzcassell/catocribbler.git
cd /opt/catocribbler/poller
```

Before doing anything else, read:

```bash
less ../DISCLAIMER.md
```

Record the commit being evaluated:

```bash
git rev-parse HEAD
```

The repository intentionally contains no `LICENSE` file. Public visibility does not grant a license from the author.

## 9. Create runtime directories

```bash
umask 077
mkdir -p secrets state
chown 10001 secrets state
chmod 0700 secrets state
```

The demonstration container runs as UID `10001`.

That UID must be able to:

- Read the API-key source file.
- Read the Cribl CA file when TLS is used.
- Create and atomically replace the marker file in `state/`.

## 10. Store the API key

Avoid shell-history exposure:

```bash
umask 077
read -rsp 'Cato API key: ' CATO_KEY
printf '%s' "$CATO_KEY" > secrets/cato_api_key
unset CATO_KEY
printf '\n'

chown 10001 secrets/cato_api_key
chmod 0400 secrets/cato_api_key
```

Verify without displaying the key:

```bash
test -s secrets/cato_api_key && echo 'Cato API key file: present'
stat -c 'owner_uid=%u mode=%a path=%n' secrets/cato_api_key
```

Expected owner UID is `10001` and mode is `400`.

## 11. Configure the Cribl CA file

The supplied Compose file declares the CA file as a secret, so the source file must exist.

### TLS test Source

```bash
install \
  -m 0400 \
  -o 10001 \
  /path/to/cribl-ca-chain.pem \
  secrets/cribl_ca.pem
```

### Isolated non-TLS lab Source

```bash
: > secrets/cribl_ca.pem
chown 10001 secrets/cribl_ca.pem
chmod 0400 secrets/cribl_ca.pem
```

Plain TCP exposes event data. Use it only in a deliberately isolated lab.

## 12. Configure `.env`

```bash
cp .env.example .env
chmod 0600 .env
nano .env
```

Example using a host-published test port:

```dotenv
CATO_API_URL=https://api.us1.catonetworks.com/api/v1/graphql2
CATO_ACCOUNT_ID=12345
CATO_API_KEY_FILE=/run/secrets/cato_api_key

CRIBL_SYSLOG_HOST=192.0.2.25
CRIBL_SYSLOG_PORT=9514
CRIBL_SYSLOG_TLS=false
CRIBL_SYSLOG_SERVER_NAME=192.0.2.25
CRIBL_SYSLOG_CA_FILE=/run/secrets/cribl_ca.pem

POLL_INTERVAL_SECONDS=30
STATE_FILE=/state/marker.txt
LOG_LEVEL=INFO
SYSLOG_HOSTNAME=cato-events-poller
```

Example using a shared test Docker network and TLS:

```dotenv
CATO_API_URL=https://api.us1.catonetworks.com/api/v1/graphql2
CATO_ACCOUNT_ID=12345
CATO_API_KEY_FILE=/run/secrets/cato_api_key

CRIBL_SYSLOG_HOST=cribl-worker
CRIBL_SYSLOG_PORT=9514
CRIBL_SYSLOG_TLS=true
CRIBL_SYSLOG_SERVER_NAME=cribl-worker.example.com
CRIBL_SYSLOG_CA_FILE=/run/secrets/cribl_ca.pem

POLL_INTERVAL_SECONDS=30
STATE_FILE=/state/marker.txt
LOG_LEVEL=INFO
SYSLOG_HOSTNAME=cato-events-poller
```

## 13. Validate files and Compose

```bash
for file in .env secrets/cato_api_key secrets/cribl_ca.pem; do
  test -e "$file" || { echo "Missing: $file"; exit 1; }
done

test -s secrets/cato_api_key || {
  echo 'The Cato API key file is empty'
  exit 1
}

sudo -u '#10001' test -r secrets/cato_api_key || {
  echo 'UID 10001 cannot read secrets/cato_api_key'
  exit 1
}

docker compose config
```

## 14. Build the demonstration image

```bash
docker compose build --pull
```

Building the poller should not stop, restart, or replace the existing Cribl containers. Review the Compose project name and commands before executing them.

## 15. Run the non-destructive Cato container preflight

```bash
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

This does not send events to Cribl and does not update the local marker, but it still queries the Cato account and may retrieve sensitive test data into memory.

## 16. Test poller-to-Cribl connectivity

```bash
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

print(socket.getaddrinfo(host, port, type=socket.SOCK_STREAM))
with socket.create_connection((host, port), timeout=5):
    print(f"CRIBL TCP PREFLIGHT PASS host={host} port={port}")
'
```

For TLS, also run the TLS preflight in [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md#12-test-cribl-tls-from-the-poller-container).

## 17. Configure the existing Cribl test environment

Before continuous polling:

1. Enable or create the Syslog TCP test Source.
2. Add the demonstration `cato_normalize` Pipeline from `cribl/pipelines/cato_normalize/conf.yml`.
3. Add the demonstration Route from `cribl/routes/cato_events_route.yml`.
4. Replace `cato_file_output` with an isolated test Destination.
5. Commit and deploy the test changes to the intended Worker Group.
6. Send the synthetic event from [`CRIBL.md`](CRIBL.md).

Do not create a second Cribl stack merely for convenience, and do not direct the demonstration into a production Destination.

## 18. Start continuous demonstration polling

```bash
docker compose up -d
docker compose ps
docker compose logs -f cato-events-poller
```

A successful test may look like:

```text
INFO starting marker_len=0
INFO Fetched=3000 Sent=3000 marker_len=180
INFO Fetched=425 Sent=425 marker_len=180
```

A full 3,000-record page is drained immediately. This can create substantial test volume and cost.

## 19. Validate the marker

```bash
ls -l state/marker.txt
wc -c state/marker.txt
```

The marker is opaque. Do not edit it or assume a fixed length.

## 20. Validate every stage in Cribl

Confirm:

- The test Syslog Source receives the connection.
- Source metrics increase.
- Live Capture shows `appname=cato-events`.
- The demonstration Route matches.
- The demonstration Pipeline promotes JSON fields.
- The isolated test Destination receives events.
- Queues remain healthy.

A poller log such as `Fetched=144 Sent=144` proves socket writes, not complete downstream delivery.

## 21. Clean up after testing

When the demonstration is complete:

```bash
cd /opt/catocribbler/poller
docker compose down
```

Then:

- Revoke the Cato API key.
- Remove the service principal if it was created only for the demonstration.
- Remove demonstration Source, Route, Pipeline, and Destination objects from Cribl when no longer needed.
- Remove the poller from the external Docker network.
- Securely dispose of the local key and copied certificates according to policy.
- Archive or destroy marker state according to the approved test plan.
- Remove the cloned repository if it is no longer required.

## No support or warranty

There is no support path for this code. Do not contact Damon Cassell, Cato Networks, Cribl, or any other party expecting assistance, fixes, compatibility updates, or incident response.

The material is provided “AS IS” and “AS AVAILABLE,” without a license grant, warranty, or liability. See [`../DISCLAIMER.md`](../DISCLAIMER.md).
