# Install the Cato poller beside an existing Cribl Docker deployment

This guide installs only the `cato-events-poller` container.

It assumes Cribl Stream is already running in Docker and that the customer will integrate this poller with an existing Cribl Worker or single-instance container.

The procedure is:

1. Inspect the existing Cribl deployment.
2. Create and validate a Cato API key.
3. Choose Docker networking between the poller and Cribl.
4. Configure the poller.
5. Test Cato and Cribl independently.
6. Start continuous polling.
7. Validate routing and destination delivery in Cribl.

## 1. Prerequisites

You need:

- Linux host access with Docker privileges.
- Docker Engine and Docker Compose v2.
- Git.
- An existing Cribl Stream Docker deployment.
- Cribl administrative access for the correct Worker Group or single instance.
- Cato administrative access to create an API key or assistance from a Cato administrator.
- Outbound HTTPS access to the correct Cato API endpoint.
- Network access from the poller container to the existing Cribl Syslog Source.

Verify local tools:

```bash
docker version
docker compose version
git --version
```

## 2. Inspect the existing Cribl containers

List the running containers:

```bash
docker ps \
  --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
```

Identify the container that receives data:

- **Single-instance deployment:** the single Cribl container.
- **Distributed deployment:** a Worker container, load balancer, or VIP serving the target Worker Group.
- Do not aim syslog at the Leader management port unless the Leader is also deliberately operating as the data-processing node.

Set the selected container name for inspection:

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
- Worker Group receiving the configuration.
- Destination used for validation.

## 3. Choose how the poller reaches Cribl

### Option A: Existing Cribl container publishes the Syslog port

Example Docker port mapping:

```text
9514/tcp -> 0.0.0.0:9514
```

Use the Docker host's LAN IP or DNS name:

```dotenv
CRIBL_SYSLOG_HOST=192.0.2.25
CRIBL_SYSLOG_PORT=9514
```

Do not use `localhost` or `127.0.0.1` in `.env`. Inside the poller container, those addresses point back to the poller itself.

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

The name resolves only when the poller and Cribl are on the same user-defined Docker network.

## 4. Confirm the existing Cribl Syslog Source

In Cribl Stream, open the single instance or target Worker Group.

Confirm or create a Syslog Source with:

| Setting | Required value |
|---|---|
| Protocol | TCP, or TCP with TLS |
| Address | `0.0.0.0` unless a deliberate narrower bind is required |
| TCP port | Commonly `9514` |
| Enabled | Yes |
| Deployed | Yes |

Current Cribl versions include a preconfigured Syslog Source on port `9514`, but it must be enabled and committed/deployed.

The repository Route does not require a specific Source ID. It matches any Cribl Syslog Source when the RFC 5424 application name is `cato-events`.

See [`CRIBL.md`](CRIBL.md) for the complete Source, Route, Pipeline, and Destination procedure.

## 5. Collect the required Cato values

You need:

- `CATO_API_URL`
- `CATO_ACCOUNT_ID`
- Cato API key

### Cato API URL

Use the endpoint assigned to the tenant. Example:

```text
https://api.us1.catonetworks.com/api/v1/graphql2
```

Some tenants or Cato examples use:

```text
https://api.catonetworks.com/api/v1/graphql2
```

Do not guess the regional hostname from geography.

### Cato account ID

Use the numeric account identifier, not the display name.

Example:

```text
12345
```

## 6. Create a Cato API key

Cato separates personal Admin API Keys from Service API Keys.

### Admin API Key for testing

1. In the Cato Management Application, go to **Resources > Admin API Keys**.
2. Select **New**.
3. Enter a descriptive name such as `cribl-eventsfeed-test`.
4. Select **Downgrade to View** because EventsFeed is a read-only query operation.
5. Optionally restrict allowed source IP addresses to the Docker host's public egress IP.
6. Set an expiration date according to policy.
7. Apply the configuration.
8. Copy the key immediately. Cato does not display it again after the dialog closes.

The key inherits the administrator's RBAC permissions and stops working if that administrator is disabled or deleted.

### Service API Key for production

A long-running shared integration should normally use a service principal.

Create the service principal:

1. Go to **Account > Administrators**.
2. Select **New**.
3. Select **Create New** and **Create as Service Principal**.
4. Enter a descriptive name such as `Cribl EventsFeed Poller`.
5. Assign the minimum role and account scope required for EventsFeed queries.
6. Apply the configuration.

Create the key:

1. Go to **Resources > Service API Keys**.
2. Select **New**.
3. Select the service principal.
4. Enter a descriptive key name.
5. Select **Downgrade to View**.
6. Optionally restrict allowed source IP addresses.
7. Set an expiration date.
8. Apply the configuration.
9. Copy the key immediately and store it securely.

The poller authenticates using:

```text
x-api-key: <api-key>
```

## 7. Authenticate directly to Cato before installing the poller

Use the direct API test in [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md#7-authenticate-directly-to-the-cato-api-endpoint).

Do not proceed until the result is:

```text
CATO API AUTHENTICATION PASS
```

This isolates Cato endpoint, account ID, RBAC, IP restrictions, and key validity before Docker and Cribl are added to the equation.

## 8. Clone the repository

Choose a protected deployment path:

```bash
sudo -i
cd /opt
git clone https://github.com/dzcassell/catocribbler.git
cd /opt/catocribbler/poller
```

Record the deployed commit:

```bash
git rev-parse HEAD
```

For production, deploy an approved commit or release rather than silently following an unreviewed moving branch.

## 9. Create runtime directories

```bash
umask 077
mkdir -p secrets state
chown 10001 secrets state
chmod 0700 secrets state
```

The container runs as UID `10001`.

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

### TLS

```bash
install \
  -m 0400 \
  -o 10001 \
  /path/to/cribl-ca-chain.pem \
  secrets/cribl_ca.pem
```

### Non-TLS lab listener

```bash
: > secrets/cribl_ca.pem
chown 10001 secrets/cribl_ca.pem
chmod 0400 secrets/cribl_ca.pem
```

Use non-TLS only on a trusted lab network.

## 12. Configure `.env`

```bash
cp .env.example .env
chmod 0600 .env
nano .env
```

Example using a Cribl host-published port:

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

Example using a shared external Docker network and TLS:

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

## 14. Build the poller image

```bash
docker compose build --pull
```

Building the poller does not stop, restart, or replace the customer's existing Cribl containers.

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

This does not send events to Cribl and does not update the marker.

## 16. Test poller-to-Cribl TCP connectivity

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

## 17. Configure the existing Cribl environment

Before starting continuous polling:

1. Enable or create the Syslog TCP Source.
2. Add the `cato_normalize` Pipeline from `cribl/pipelines/cato_normalize/conf.yml`.
3. Add the Route from `cribl/routes/cato_events_route.yml`.
4. Replace `cato_file_output` with the customer's validation or production Destination.
5. Commit and deploy the changes to the target Worker Group.
6. Send the synthetic event from [`CRIBL.md`](CRIBL.md).

Do not create a second Cribl stack for this project. Integrate these objects into the existing environment.

## 18. Start continuous polling

```bash
docker compose up -d
docker compose ps
docker compose logs -f cato-events-poller
```

Healthy startup:

```text
INFO starting marker_len=0
INFO Fetched=3000 Sent=3000 marker_len=180
INFO Fetched=425 Sent=425 marker_len=180
```

A full 3,000-record page is drained immediately. The normal polling delay begins after a smaller page.

## 19. Validate the marker

```bash
ls -l state/marker.txt
wc -c state/marker.txt
```

The marker is opaque. Do not edit it or assume a fixed length.

## 20. Validate end to end in Cribl

Confirm:

- The existing Syslog Source receives the connection.
- Source metrics increase.
- Live Capture shows `appname=cato-events`.
- The Cato Route matches.
- `cato_normalize` promotes the JSON fields.
- The chosen Destination receives the events.
- Destination queues are healthy.

A poller log such as `Fetched=144 Sent=144` proves successful socket writes, not complete downstream delivery.

## 21. Migrating from another poller

To avoid replay:

1. Stop the old poller.
2. Copy its current Cato marker to `poller/state/marker.txt`.
3. Assign ownership to UID `10001`.
4. Start this poller.
5. Confirm matching `Fetched` and `Sent` counts.
6. Validate Cribl destination delivery.
7. Remove the old poller only after successful validation.

Example:

```bash
install \
  -m 0600 \
  -o 10001 \
  /path/to/existing-marker.txt \
  state/marker.txt

docker compose up -d
```

Never run two independent pollers against the same account and marker state unless duplicate delivery is intentional.

## Related guides

- [`CRIBL.md`](CRIBL.md): configure the existing Cribl deployment.
- [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md): API authentication, Docker networking, TLS, routing, and diagnostic commands.
- [`OPERATIONS.md`](OPERATIONS.md): upgrades, backup, recovery, and monitoring.
- [`../SECURITY.md`](../SECURITY.md): credential and deployment security.
