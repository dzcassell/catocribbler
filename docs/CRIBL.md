# Demonstration integration with an existing Cribl Stream Docker environment

> [!CAUTION]
> **UNSUPPORTED, NON-PRODUCTION DEMONSTRATION ONLY.** This material is not supported, approved, endorsed, maintained, or warranted by Damon Cassell, Cato Networks, Cribl, any employer, contributor, vendor, partner, or anyone else. There is no license grant. Do not apply these changes to a production Cribl environment. Read [`../DISCLAIMER.md`](../DISCLAIMER.md).

This guide assumes Cribl Stream already runs in Docker. The repository and installer add only the experimental `cato-events-poller` container and demonstration Cribl configuration.

The default installation directory is `/opt/cribbler`, but the installer allows another absolute path.

```bash
INSTALL_DIR=${INSTALL_DIR:-/opt/cribbler}
POLLER_DIR="${INSTALL_DIR}/poller"
```

## 1. Identify the Cribl data-processing container

```bash
docker ps \
  --filter 'name=cribl' \
  --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
```

Choose:

- The non-production single-instance Cribl container, or
- A non-production Worker, Worker load balancer, or VIP for the intended test Worker Group.

Do not use the Leader management port unless that node intentionally processes test data.

Inspect the selected container:

```bash
CRIBL_CONTAINER=cribl-worker

docker inspect "${CRIBL_CONTAINER}" \
  --format 'Name={{.Name}}
Networks={{json .NetworkSettings.Networks}}
Ports={{json .NetworkSettings.Ports}}'

docker port "${CRIBL_CONTAINER}"
```

## 2. Choose the poller connection model

### Published host TCP port, recommended default

Use this when the Cribl container publishes the Syslog Source port to the Docker host, for example:

```text
0.0.0.0:9514->9514/tcp
```

Installer values:

```text
Connection method: 1
Cribl host: <docker-host-lan-ip-or-dns-name>
Cribl port: 9514
```

This is the recommended default because it:

- Is simpler to explain and troubleshoot.
- Does not attach the poller to Cribl's internal Docker network.
- Does not depend on local Docker network names and aliases.
- Works when the poller runs on the same host or another reachable test host.

Do not use `localhost` or `127.0.0.1`; inside the poller container those addresses refer to the poller itself.

### Shared external Docker network, advanced fallback

Use this only when the Syslog TCP port is not published or direct container-to-container connectivity is specifically required.

Installer values:

```text
Connection method: 2
Docker network: <existing-cribl-test-network>
Cribl host: <container-service-or-network-alias>
Cribl port: 9514
```

The installer verifies the network exists and writes:

```text
<install-directory>/poller/compose.override.yaml
```

This option:

- Depends on customer-specific Docker network names and aliases.
- Gives the poller access to other services exposed on that network.
- Is less portable between customer environments.

**Recommendation:** choose option 1 unless the Cribl listener is not published or the deployment specifically requires option 2.

## 3. Reuse or create a non-production Syslog Source

Confirm:

| Setting | Demonstration value |
|---|---|
| Source type | Syslog |
| Protocol | TCP, or TCP with TLS |
| Address | `0.0.0.0` unless deliberately restricted |
| TCP port | `9514` or another approved test port |
| Enabled | Yes |
| Configuration state | Saved, committed, and deployed |
| Data scope | Synthetic or specifically approved test data |

The poller emits RFC 5424 records with:

```text
appname=cato-events
```

The supplied Route accepts any Syslog Source ID and narrows on this application name.

## 4. Confirm Docker exposes the listener

For the recommended published-port model:

```bash
docker port "${CRIBL_CONTAINER}" 9514/tcp
ss -lnt | grep ':9514 '
```

If the Source is enabled inside Cribl but the TCP port is not published, either:

- Add an approved test-only port mapping, or
- Use the shared external Docker network model.

Do not launch a replacement Cribl stack or expose Cribl management ports for this demonstration.

## 5. TLS settings

When TLS is enabled, the installer asks for:

- The Cribl certificate server name
- A PEM CA chain file that validates the server certificate

The certificate should:

- Contain the configured server name in its SAN
- Be within its validity period
- Include required intermediates
- Chain to the supplied CA file

The poller validates the Cribl server certificate. It does not present a client certificate, so mandatory mutual TLS is not supported by the demonstration code.

Plain TCP exposes event contents and should be used only on a deliberately isolated test network.

## 6. Add the normalization Pipeline

Repository file:

```text
cribl/pipelines/cato_normalize/conf.yml
```

Create or import a Pipeline with ID:

```text
cato_normalize
```

The demonstration Pipeline attempts to:

1. Parse JSON from the syslog `message` field.
2. Confirm the payload is an object.
3. Promote JSON properties to top-level fields.
4. Add `cribl_pipeline=cato_normalize`.
5. Add `vendor=cato` and `product=cato_sase` when absent.
6. Convert numeric Cato time to Cribl `_time` when possible.
7. Write normalized JSON to `_raw`.
8. Remove the original `message` field.
9. Set `cato_parse_error` if parsing fails.

## 7. Add the Route

Repository file:

```text
cribl/routes/cato_events_route.yml
```

Route filter:

```javascript
__inputId.startsWith('syslog:') && appname === 'cato-events'
```

Suggested settings:

| Setting | Demonstration value |
|---|---|
| Route ID | `cato_events_route` |
| Pipeline | `cato_normalize` |
| Output | Isolated test Destination |
| Final | Yes |
| Enabled | Yes |

Replace the example output ID `cato_file_output` with the actual isolated test Destination when necessary.

Place the Route before broad final routes that might consume the event first.

## 8. Commit and deploy only to the test Worker Group

In a distributed test deployment:

1. Save the Source, Pipeline, Route, and Destination changes.
2. Review the configuration diff.
3. Commit the test configuration.
4. Deploy only to the intended test Worker Group.
5. Confirm the Worker reports the configuration as active.

A configuration visible in the UI but not deployed is not active.

## 9. Test with the installer

The interactive installer automatically:

1. Builds the poller image.
2. Runs the Cato EventsFeed preflight without sending records.
3. Opens the configured Cribl TCP or TLS socket.
4. Offers to send one synthetic event.
5. Leaves continuous polling stopped unless the evaluator types `START`.

See [`INSTALLER.md`](INSTALLER.md) and [`INSTALL.md`](INSTALL.md).

## 10. Re-run the Cribl connection preflight

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

## 11. Send a synthetic event

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

Validate:

- Source receives the event.
- `appname` is `cato-events`.
- `cato_events_route` matches.
- `cato_normalize` runs.
- `event_type` is `Catocribbler Installer Synthetic Test`.
- Isolated test Destination receives the event.

## 12. Start continuous polling

```bash
cd "${POLLER_DIR}"
docker compose up -d
docker compose logs -f cato-events-poller
```

A successful cycle resembles:

```text
INFO Fetched=144 Sent=144 marker_len=180
```

A new installation begins with an empty marker and may immediately drain retained events in pages of up to 3,000.

`Fetched=N Sent=N` proves only that the records were written to the Cribl socket.

## 13. Validate every Cribl stage

Confirm:

1. Source connection count increases.
2. Source event count increases.
3. Live Capture shows approved test records.
4. Route match count increases.
5. Pipeline adds `cribl_pipeline=cato_normalize`.
6. Unexpected `cato_parse_error` values do not appear.
7. Isolated Destination receives events.
8. Queues, storage, and licensing remain within approved limits.

## 14. Common failures

### Source receives nothing

Check:

- Correct Docker host or shared network
- Correct TCP port
- Port publication
- TCP rather than UDP-only configuration
- Source enabled and deployed
- TLS settings
- Firewall and Docker routing

### Source receives events but Route does not match

Check:

- `appname=cato-events`
- `__inputId` begins with `syslog:`
- Route order
- Earlier final routes
- Correct Worker Group deployment

### Route matches but Pipeline fails

Inspect:

```text
cato_parse_error
cribl_pipeline=cato_normalize_parse_failed
```

### Pipeline succeeds but Destination receives nothing

Check:

- Route output ID
- Destination health and credentials
- Backpressure and persistent queues
- Destination-side filters
- Storage and evaluation-license capacity

### TCP works but TLS fails

Check:

- TLS is enabled on the exact Source port
- Server name matches a certificate SAN
- CA chain is correct
- Certificate is current
- Source is not requiring a client certificate

## 15. Remove the demonstration

```bash
cd "${POLLER_DIR}"
docker compose down
```

Then revoke the Cato key, remove the demonstration service principal when appropriate, remove test-only Cribl objects, detach external Docker networks, and destroy test credentials and data according to policy.

## No support, license, or warranty

No support is provided by Damon Cassell, Cato Networks, Cribl, contributors, employers, vendors, or any other party. All material is provided “AS IS” and “AS AVAILABLE.” Read [`../DISCLAIMER.md`](../DISCLAIMER.md).
