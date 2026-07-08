# Integrate the poller with an existing Cribl Stream Docker environment

This guide does not deploy Cribl Stream.

It assumes the customer already has Cribl Stream running in Docker and needs to add the Cato poller as a new upstream syslog sender.

## 1. Identify the existing Cribl data-processing container

List the containers:

```bash
docker ps \
  --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
```

Choose the correct target:

- Single-instance Cribl: the single Cribl container.
- Distributed Cribl: a Worker container, Worker load balancer, or VIP for the target Worker Group.
- Do not use the Leader management port as the syslog destination unless that node is intentionally processing data.

Inspect the target:

```bash
CRIBL_CONTAINER=cribl-worker

docker inspect "$CRIBL_CONTAINER" \
  --format 'Name={{.Name}}
Networks={{json .NetworkSettings.Networks}}
Ports={{json .NetworkSettings.Ports}}'

docker port "$CRIBL_CONTAINER"
```

## 2. Decide how the poller connects

### Published host port

If the existing Cribl container publishes TCP 9514, use the Docker host's LAN IP address or DNS name:

```dotenv
CRIBL_SYSLOG_HOST=192.0.2.25
CRIBL_SYSLOG_PORT=9514
```

Typical Docker mapping:

```text
0.0.0.0:9514->9514/tcp
```

Do not configure `localhost` or `127.0.0.1`; inside the poller container those point to the poller itself.

### Existing shared Docker network

Attach the poller to the Cribl network with `poller/compose.override.yaml`:

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

Then use the Cribl container/service name:

```dotenv
CRIBL_SYSLOG_HOST=cribl-worker
CRIBL_SYSLOG_PORT=9514
```

See [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md#3-choose-the-docker-connectivity-model) for discovery and validation commands.

## 3. Reuse or enable the existing Syslog Source

Current Cribl Stream versions include a preconfigured Syslog Source on port `9514`. The customer can reuse it, clone it, or create another Source.

In the target Worker Group or single instance, confirm:

| Setting | Value |
|---|---|
| Source type | Syslog |
| Protocol | TCP, or TCP with TLS |
| Address | `0.0.0.0` unless deliberately restricted |
| TCP port | `9514` or another agreed port |
| Enabled | Yes |
| Configuration state | Saved, committed, and deployed |

The poller sends RFC 5424 records.

The Source ID can be `in_syslog_default`, `in_syslog`, or a customer-defined value. The repository Route accepts any Syslog Source ID and identifies this integration by:

```javascript
appname === 'cato-events'
```

## 4. Confirm Docker exposes the listener

For the host-published-port model:

```bash
docker port "$CRIBL_CONTAINER" 9514/tcp
ss -lnt | grep ':9514 '
```

If the Source is enabled inside Cribl but Docker does not publish the port, either:

- Add the port mapping to the customer's existing Cribl Compose or Docker configuration, or
- Use the shared external Docker network model.

Do not launch a replacement Cribl container merely to expose one port. That is the sort of solution that wins a five-minute demo and ruins the following week.

## 5. Configure TLS when required

For production, use TLS unless the customer's network design explicitly permits plain TCP.

The existing Cribl Syslog Source must have TLS enabled on the selected TCP port.

The poller needs:

```dotenv
CRIBL_SYSLOG_TLS=true
CRIBL_SYSLOG_HOST=cribl-worker.example.com
CRIBL_SYSLOG_SERVER_NAME=cribl-worker.example.com
CRIBL_SYSLOG_CA_FILE=/run/secrets/cribl_ca.pem
```

The certificate must:

- Contain the configured server name in its SAN.
- Be within its validity period.
- Include required intermediates.
- Chain to the CA in `poller/secrets/cribl_ca.pem`.

The current poller validates the server certificate. It does not present a client certificate, so do not enable mandatory mutual TLS on the Cribl Source unless the poller is extended for client-certificate authentication.

For a non-TLS lab Source:

```dotenv
CRIBL_SYSLOG_TLS=false
```

## 6. Add the normalization Pipeline to the existing environment

Use:

```text
cribl/pipelines/cato_normalize/conf.yml
```

Create or import a Pipeline with ID:

```text
cato_normalize
```

The Pipeline:

1. Parses the JSON payload from the syslog `message` field.
2. Verifies the payload is an object.
3. Promotes JSON properties to top-level Cribl fields.
4. Adds `cribl_pipeline=cato_normalize`.
5. Adds `vendor=cato` and `product=cato_sase` when absent.
6. Converts a numeric Cato `time` value to Cribl `_time` when possible.
7. Writes normalized JSON to `_raw`.
8. Removes the original `message` field.
9. Sets `cato_parse_error` if parsing fails.

Expected pre-Pipeline fields include:

```text
appname = cato-events
host = cato-events-poller
message = {"time":...,"event_type":...,"vendor":"cato",...}
```

Expected post-Pipeline fields include:

```json
{
  "event_type": "Security",
  "event_sub_type": "Anti Malware",
  "account_id": "12345",
  "vendor": "cato",
  "product": "cato_sase",
  "cribl_pipeline": "cato_normalize"
}
```

## 7. Add the Route to the existing Worker Group

Use:

```text
cribl/routes/cato_events_route.yml
```

The Route filter is:

```javascript
__inputId.startsWith('syslog:') && appname === 'cato-events'
```

Recommended settings:

| Setting | Value |
|---|---|
| Route ID | `cato_events_route` |
| Filter | `__inputId.startsWith('syslog:') && appname === 'cato-events'` |
| Pipeline | `cato_normalize` |
| Output | Customer validation or production Destination |
| Final | Yes |
| Enabled | Yes |

Replace the example output ID:

```text
cato_file_output
```

with the customer's actual Destination ID.

Place the Route before broad catch-all routes that might consume the event first.

## 8. Use an existing or temporary validation Destination

The customer may already have a production Destination. For initial validation, a temporary filesystem or other controlled Destination is useful because it proves Source, Route, Pipeline, and output delivery.

Confirm the Destination:

- Is enabled.
- Is healthy.
- Has valid credentials.
- Has sufficient capacity for an initial EventsFeed backlog.
- Is assigned as the Cato Route output.

## 9. Commit and deploy changes

In a distributed deployment:

1. Save the Source, Pipeline, Route, and Destination changes.
2. Commit the configuration.
3. Deploy to the target Worker Group.
4. Confirm the Worker reports the new configuration as active.

A configuration visible in the UI but not deployed is not active. Cribl remains stubbornly attached to reality in this respect.

## 10. Test connectivity before starting the poller

From the poller directory:

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

print(socket.getaddrinfo(host, port, type=socket.SOCK_STREAM))
with socket.create_connection((host, port), timeout=5):
    print(f"CRIBL TCP PREFLIGHT PASS host={host} port={port}")
'
```

For TLS, run the TLS preflight in [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md#12-test-cribl-tls-from-the-poller-container).

## 11. Send a synthetic RFC 5424 event

Plain TCP example:

```bash
printf '<134>1 2026-01-01T00:00:00.000Z test-host cato-events - - - {"time":1767225600000,"event_type":"Synthetic Test","vendor":"cato","product":"cato_sase"}\n' \
  | nc <cribl-host> 9514
```

Validate in Cribl:

- Syslog Source receives the event.
- `appname` is `cato-events`.
- `cato_events_route` matches.
- `cato_normalize` runs.
- `event_type` is `Synthetic Test`.
- The selected Destination receives the event.

## 12. Start the Cato poller

```bash
cd /opt/catocribbler/poller
docker compose up -d
docker compose logs -f cato-events-poller
```

Healthy output:

```text
INFO Fetched=144 Sent=144 marker_len=180
```

## 13. Validate every Cribl stage

Do not stop at the poller log.

Confirm:

1. Source connection count increases.
2. Source received-event count increases.
3. Live Capture shows Cato records.
4. Route match count increases.
5. Pipeline adds `cribl_pipeline=cato_normalize`.
6. No unexpected `cato_parse_error` fields appear.
7. Destination delivered-event count increases.
8. Persistent queues and backpressure remain healthy.

`Fetched=144 Sent=144` means the poller wrote 144 records to the TCP socket. It does not prove downstream delivery.

## 14. Common existing-environment failures

### Cribl Source receives nothing

Check:

- Correct Docker host IP or shared network.
- TCP port is published or shared-network DNS works.
- Source is enabled and deployed.
- Source listens on TCP rather than only UDP.
- Source address is not restricted to an unreachable interface.
- TLS settings match.

### Source receives the event but Route does not match

Inspect:

- `appname` equals `cato-events`.
- `__inputId` starts with `syslog:`.
- Route order.
- Earlier final routes.

### Route matches but Pipeline fails

Look for:

```text
cato_parse_error
cribl_pipeline=cato_normalize_parse_failed
```

Capture the pre-Pipeline event and confirm `message` contains one complete JSON object.

### Pipeline succeeds but Destination receives nothing

Check:

- Route output ID.
- Destination health and credentials.
- Backpressure and persistent queues.
- Destination-side filters.
- Storage and licensing capacity.

### TCP works but TLS fails

Check:

- Cribl TLS is enabled on the exact port.
- Poller has `CRIBL_SYSLOG_TLS=true`.
- Server name matches certificate SAN.
- CA chain is correct.
- Source is not requiring a client certificate.

## Related guides

- [`INSTALL.md`](INSTALL.md): install and configure the poller.
- [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md): complete Cato API, Docker network, Cribl, TLS, and permissions troubleshooting.
- [`OPERATIONS.md`](OPERATIONS.md): upgrades, backup, recovery, and monitoring.
