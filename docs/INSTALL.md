# Installation and Cato tenant configuration

This guide installs the `cato-events-poller` container and configures it to retrieve EventsFeed records from one Cato tenant and send them to a Cribl Stream Syslog Source.

## 1. Prerequisites

You need:

- A Linux host with outbound HTTPS access to the tenant's Cato API endpoint.
- Network access from the Docker host to the Cribl Stream Syslog Source.
- Docker Engine.
- Docker Compose v2, invoked as `docker compose`.
- Git.
- A Cato administrator who can enable EventsFeed and create an API key.
- A Cribl administrator who can configure a Syslog Source, Route, Pipeline, and Destination.

Verify the local tools:

```bash
docker version
docker compose version
git --version
```

## 2. Collect the required Cato tenant values

The deployment requires three tenant-specific Cato values:

1. Cato API URL
2. Cato account ID
3. Cato API key

### 2.1 Confirm that EventsFeed is enabled

The Cato tenant must have EventsFeed enabled. The exact management-screen names can vary as the Cato Management Application changes, so confirm with the tenant administrator that:

- EventsFeed is enabled for the target account.
- Events are entering the feed.
- The API key is permitted to read EventsFeed data.

If EventsFeed is not enabled or the key lacks access, the container cannot retrieve logs regardless of how enthusiastically Docker reports that it is running.

### 2.2 Obtain the Cato account ID

`CATO_ACCOUNT_ID` is the numeric account identifier used by the Cato API. It is not the tenant display name.

Common places to find it include:

- The account identifier shown in the Cato Management Application URL while the target tenant is selected.
- Cato API tooling or API Explorer output.
- Existing Cato API scripts or integrations for the same tenant.
- The tenant's API-management information.

Record only the numeric value. Example:

```text
12345
```

Do not include brackets, quotation marks, or labels in `.env`.

### 2.3 Create a Cato API key

In the Cato Management Application, open the tenant's API-management area and create a service API key for this integration.

Recommended settings:

- Use a descriptive name, such as `cribl-eventsfeed-poller`.
- Grant only the permissions required to read EventsFeed data for the target account.
- Restrict allowed source IP addresses when the tenant's API-key controls support it.
- Set an expiration and rotation process that matches organizational policy.
- Store the key in an approved password vault or secret-management platform.

The API key is placed in a file named:

```text
poller/secrets/cato_api_key
```

It is deliberately not placed in `.env`, the Dockerfile, or the image.

### 2.4 Determine the correct Cato API URL

`CATO_API_URL` must be the GraphQL endpoint assigned to the tenant's region.

Example for a US1 tenant:

```text
https://api.us1.catonetworks.com/api/v1/graphql2
```

Some Cato examples and tenants use:

```text
https://api.catonetworks.com/api/v1/graphql2
```

Use the exact endpoint appropriate for the target tenant. Do not infer the region from geography alone. Reuse the endpoint from a known-working integration or confirm it with the tenant administrator.

## 3. Prepare Cribl first

Before starting the poller, configure the Cribl side so the destination is ready to accept events.

At minimum, create:

- A Syslog Source that listens on TCP or TLS.
- A Route matching `appname === 'cato-events'`.
- The supplied `cato_normalize` Pipeline.
- A validation or production Destination.

See [`CRIBL.md`](CRIBL.md) for the full procedure.

Record these values:

- Cribl listener hostname or IP address
- Listener TCP port
- Whether TLS is enabled
- TLS server name, if applicable
- CA certificate chain used to validate the Cribl certificate

The hostname must be reachable from inside the Docker container. If Cribl runs on the same physical host but outside this Compose project, use a host address that the container can reach, such as the Docker host's LAN address. Do not use `127.0.0.1` unless Cribl is running inside the same container, which it should not be.

## 4. Clone the repository

Choose a protected deployment directory. The examples use `/opt/catocribbler`.

```bash
sudo -i
cd /opt
git clone https://github.com/dzcassell/catocribbler.git
cd /opt/catocribbler/poller
```

For a reproducible production deployment, check out an approved commit or release rather than following an unreviewed moving branch:

```bash
git rev-parse HEAD
```

Record that commit in the change ticket.

## 5. Create the runtime directories

From `poller/`:

```bash
umask 077
mkdir -p secrets state
```

The container runs as UID `10001`. That UID must be able to read the local secret source files and create and atomically replace the marker file.

```bash
chown 10001 secrets state
chmod 0700 secrets state
```

The host may display an unexpected group name on `state/marker.txt` after the container writes it. Numeric UID ownership and successful marker updates are what matter.

## 6. Store the Cato API key

The safest simple interactive method avoids putting the key in shell history:

```bash
umask 077
read -rsp "Cato API key: " CATO_KEY
printf '%s' "$CATO_KEY" > secrets/cato_api_key
unset CATO_KEY
printf '\n'
chown 10001 secrets/cato_api_key
chmod 0400 secrets/cato_api_key
```

Confirm that the file exists without displaying its contents:

```bash
test -s secrets/cato_api_key && echo "Cato API key file: present"
wc -c secrets/cato_api_key
stat -c 'owner_uid=%u mode=%a path=%n' secrets/cato_api_key
```

Expected ownership is UID `10001`, with mode `400`.

Do not run `cat secrets/cato_api_key` in a recorded terminal session.

A production secret-management system may write the same file during deployment instead of using the interactive method, but it must preserve equivalent ownership and permissions for this local Compose deployment.

## 7. Configure the Cribl CA file

The supplied Compose file declares a `cribl_ca` secret, so the source file must exist in both TLS and non-TLS deployments.

### TLS deployment

Copy the PEM-encoded CA certificate or CA chain that validates the Cribl Syslog Source certificate:

```bash
install -m 0400 -o 10001 /path/to/cribl-ca-chain.pem secrets/cribl_ca.pem
```

The certificate's server name must match `CRIBL_SYSLOG_SERVER_NAME`.

### Non-TLS lab deployment

Create an empty placeholder and disable TLS in `.env`:

```bash
: > secrets/cribl_ca.pem
chown 10001 secrets/cribl_ca.pem
chmod 0400 secrets/cribl_ca.pem
```

Plain TCP is appropriate only on a trusted lab network. Use TLS for production traffic.

## 8. Create and edit `.env`

Copy the template:

```bash
cp .env.example .env
chmod 0600 .env
```

Edit it with a local editor:

```bash
nano .env
```

Example TLS configuration:

```dotenv
CATO_API_URL=https://api.us1.catonetworks.com/api/v1/graphql2
CATO_ACCOUNT_ID=12345
CATO_API_KEY_FILE=/run/secrets/cato_api_key

CRIBL_SYSLOG_HOST=cribl-worker.example.com
CRIBL_SYSLOG_PORT=9514
CRIBL_SYSLOG_TLS=true
CRIBL_SYSLOG_SERVER_NAME=cribl-worker.example.com
CRIBL_SYSLOG_CA_FILE=/run/secrets/cribl_ca.pem

POLL_INTERVAL_SECONDS=30
STATE_FILE=/state/marker.txt
LOG_LEVEL=INFO
SYSLOG_HOSTNAME=cato-events-poller
```

Example non-TLS lab configuration:

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

### Configuration reference

| Variable | Required | Purpose |
|---|---:|---|
| `CATO_API_URL` | Yes | Full Cato GraphQL endpoint, including `/api/v1/graphql2`. |
| `CATO_ACCOUNT_ID` | Yes | Numeric Cato account ID for the tenant being polled. |
| `CATO_API_KEY_FILE` | Yes | In-container path to the API-key secret. Leave as `/run/secrets/cato_api_key` with the supplied Compose file. |
| `CRIBL_SYSLOG_HOST` | Yes | DNS name or IP address reachable from the container. |
| `CRIBL_SYSLOG_PORT` | No | Cribl TCP listener port. Default is `9514`. |
| `CRIBL_SYSLOG_TLS` | No | `true` or `false`. Default is `true`. |
| `CRIBL_SYSLOG_SERVER_NAME` | No | TLS certificate server name. Defaults to `CRIBL_SYSLOG_HOST`. |
| `CRIBL_SYSLOG_CA_FILE` | No | In-container CA file used for TLS validation. Normally `/run/secrets/cribl_ca.pem`. |
| `POLL_INTERVAL_SECONDS` | No | Delay after a non-full EventsFeed page. Default is `30`. |
| `STATE_FILE` | No | Marker path inside the container. Leave as `/state/marker.txt`. |
| `LOG_LEVEL` | No | Python log level, normally `INFO`. |
| `SYSLOG_HOSTNAME` | No | Hostname written into the RFC 5424 message. Default is `cato-events-poller`. |

The file-path variables are container paths, not host paths.

## 9. Validate the deployment files

Check that required files exist and the API key is readable by UID `10001`:

```bash
for file in .env secrets/cato_api_key secrets/cribl_ca.pem; do
  test -e "$file" || { echo "Missing: $file"; exit 1; }
done

test -s secrets/cato_api_key || {
  echo "The Cato API key file is empty"
  exit 1
}

sudo -u '#10001' test -r secrets/cato_api_key || {
  echo "UID 10001 cannot read secrets/cato_api_key"
  exit 1
}
```

Validate the effective Compose configuration:

```bash
docker compose config
```

This command should complete without printing the API key.

## 10. Optional non-destructive API preflight

The preflight calls Cato and decodes one page, but it does not send events to Cribl and does not update the marker:

```bash
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

A successful preflight looks like:

```text
CATO API PREFLIGHT PASS fetched=250 decoded=250 current_marker_len=180 returned_marker_len=180
```

A first-run preflight with an empty marker may return 3,000 events because that is a full EventsFeed page.

## 11. Optional Cribl TCP preflight

Test network connectivity without sending an event:

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

with socket.create_connection((host, port), timeout=5):
    print(f"CRIBL TCP PREFLIGHT PASS host={host} port={port}")
'
```

This verifies only that a TCP connection can be established. It does not validate TLS, Cribl routing, or destination delivery.

## 12. Start the poller

```bash
docker compose build --pull
docker compose up -d
```

Check status:

```bash
docker compose ps
```

Follow the logs:

```bash
docker compose logs -f cato-events-poller
```

Healthy startup and polling look like:

```text
INFO starting marker_len=0
INFO Fetched=3000 Sent=3000 marker_len=180
INFO Fetched=425 Sent=425 marker_len=180
```

The poller does not sleep after a full 3,000-event page. It immediately requests the next page until the backlog is drained.

## 13. Validate the marker

After the first successful page, confirm that the marker exists:

```bash
ls -l state/marker.txt
wc -c state/marker.txt
```

The marker is an opaque Cato value. Do not edit it. Its size can change between API versions or tenants.

## 14. Validate in Cribl

Confirm all of the following:

- The Syslog Source receives connections and events.
- The Route matches `appname === 'cato-events'`.
- The `cato_normalize` Pipeline parses the JSON payload.
- Expected Cato fields are promoted to top-level fields.
- The selected Destination receives the same events.

See [`CRIBL.md`](CRIBL.md).

## 15. Install as an automatically restarting service

The Compose file uses:

```yaml
restart: unless-stopped
```

Docker will restart the container after a process failure or host reboot, provided the Docker service itself starts normally.

Verify Docker startup on systemd hosts:

```bash
systemctl is-enabled docker
systemctl status docker --no-pager
```

## 16. Protect the deployment directory

The deployment directory contains sensitive runtime material. Recommended host permissions:

```bash
chown 10001 /opt/catocribbler/poller/secrets/cato_api_key
chown 10001 /opt/catocribbler/poller/secrets/cribl_ca.pem
chown 10001 /opt/catocribbler/poller/state

chmod 0700 /opt/catocribbler/poller
chmod 0600 /opt/catocribbler/poller/.env
chmod 0400 /opt/catocribbler/poller/secrets/cato_api_key
chmod 0400 /opt/catocribbler/poller/secrets/cribl_ca.pem
chmod 0700 /opt/catocribbler/poller/state
```

Do not loosen permissions merely to make casual non-root inspection more convenient. Use an administrative account for deployment management.

## 17. Migrating from another poller

To avoid replaying events:

1. Stop the old poller.
2. Copy its current Cato marker to `poller/state/marker.txt`.
3. Make the file and directory writable by UID `10001`.
4. Start this poller.
5. Confirm `Fetched=N Sent=N` before removing the old integration.

Example:

```bash
docker compose down
install -m 0600 -o 10001 /path/to/existing-marker.txt state/marker.txt
chown 10001 state
docker compose up -d
```

Never run two pollers against the same tenant and marker state unless duplicate delivery and marker races are intentional.

## Next steps

- Configure Cribl using [`CRIBL.md`](CRIBL.md).
- Learn upgrades and recovery procedures in [`OPERATIONS.md`](OPERATIONS.md).
- Review [`../SECURITY.md`](../SECURITY.md) before production deployment.
