# Demonstration integration with an existing Cribl Stream Docker environment

> [!CAUTION]
> **UNSUPPORTED, NON-PRODUCTION DEMONSTRATION ONLY.** This material is not supported, approved, endorsed, maintained, or warranted by Damon Cassell, Cato Networks, Cribl, any employer, contributor, vendor, partner, or anyone else. There is no license grant. Do not apply these changes to a production Cribl environment. Read [`../DISCLAIMER.md`](../DISCLAIMER.md).

This guide does not deploy Cribl Stream.

It assumes an evaluator already has Cribl Stream running in Docker and is adding the experimental Cato poller to an isolated, disposable, non-production Cribl environment.

The configuration examples in this repository have not been reviewed or certified by Cribl. They can misroute, duplicate, drop, expose, delay, or corrupt events and can affect licensing, queues, storage, downstream systems, and availability.

## 1. Identify the non-production Cribl data-processing container

List containers:

```bash
docker ps \
  --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
```

Choose the correct test target:

- Single-instance Cribl: the non-production single Cribl container.
- Distributed Cribl: a test Worker container, Worker load balancer, or VIP for the test Worker Group.
- Do not use the Leader management port as the syslog destination unless that node is intentionally processing test data.

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

### Published test-host port

If the existing test Cribl container publishes TCP 9514, use the Docker host's test-network IP or DNS name:

```dotenv
CRIBL_SYSLOG_HOST=192.0.2.25
CRIBL_SYSLOG_PORT=9514
```

Typical mapping:

```text
0.0.0.0:9514->9514/tcp
```

Do not configure `localhost` or `127.0.0.1`; inside the poller container those point to the poller itself.

### Shared external Docker network

Attach the poller to the isolated Cribl test network with `poller/compose.override.yaml`:

```yaml
services:
  cato-events-poller:
    networks:
      - cribl_existing

networks:
  cribl_existing:
    external: true
    name: <actual-existing-cribl-test-network-name>
```

Then use the Cribl container or service name:

```dotenv
CRIBL_SYSLOG_HOST=cribl-worker
CRIBL_SYSLOG_PORT=9514
```

Attaching the demonstration container to an existing network increases its reach. Review the network membership and do not attach it to production, management, database, or unrelated application networks.

See [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md#3-choose-the-docker-connectivity-model) for discovery and validation commands.

## 3. Reuse or enable a non-production Syslog Source

A Cribl deployment may include a preconfigured Syslog Source on port `9514`. Reuse, clone, or create a Source only in the authorized test environment.

Confirm:

| Setting | Demonstration value |
|---|---|
| Source type | Syslog |
| Protocol | TCP, or TCP with TLS |
| Address | `0.0.0.0` unless deliberately restricted |
| TCP port | `9514` or another approved test port |
| Enabled | Yes |
| Configuration state | Saved, committed, and deployed |
| Data scope | Synthetic or specifically approved test data only |

The poller sends RFC 5424 records.

The Source ID can be `in_syslog_default`, `in_syslog`, or another value. The demonstration Route accepts any Syslog Source ID and identifies the poller using:

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

- Add an approved test-only port mapping to the existing non-production Cribl configuration, or
- Use the shared test-network model.

Do not launch a replacement Cribl container, alter production port mappings, or expose management ports for this demonstration.

## 5. Configure TLS for the test when required

TLS is strongly preferred even in a lab when real event data might traverse the connection. TLS does not make this demonstration production-ready.

The Cribl test Source must have TLS enabled on the selected TCP port.

The poller needs:

```dotenv
CRIBL_SYSLOG_TLS=true
CRIBL_SYSLOG_HOST=cribl-worker.example.com
CRIBL_SYSLOG_SERVER_NAME=cribl-worker.example.com
CRIBL_SYSLOG_CA_FILE=/run/secrets/cribl_ca.pem
```

The certificate should:

- Contain the configured server name in its SAN.
- Be within its validity period.
- Include required intermediates.
- Chain to the CA in `poller/secrets/cribl_ca.pem`.

The demonstration poller validates the server certificate. It does not present a client certificate. Do not enable mandatory mutual TLS unless the code is independently modified, reviewed, and tested.

For an isolated non-TLS lab Source:

```dotenv
CRIBL_SYSLOG_TLS=false
```

Plain TCP can expose event contents and should never be used across an untrusted network.

## 6. Add the demonstration normalization Pipeline

Use:

```text
cribl/pipelines/cato_normalize/conf.yml
```

Create or import a test Pipeline with ID:

```text
cato_normalize
```

The demonstration Pipeline attempts to:

1. Parse JSON from the syslog `message` field.
2. Verify that the payload is an object.
3. Promote JSON properties to top-level Cribl fields.
4. Add `cribl_pipeline=cato_normalize`.
5. Add `vendor=cato` and `product=cato_sase` when absent.
6. Convert a numeric Cato `time` value to Cribl `_time` when possible.
7. Write normalized JSON to `_raw`.
8. Remove the original `message` field.
9. Set `cato_parse_error` if parsing fails.

This code has not been validated against every Cato event type, schema variation, Cribl release, malformed record, or downstream requirement.

Expected pre-Pipeline fields may resemble:

```text
appname = cato-events
host = cato-events-poller
message = {"time":...,"event_type":...,"vendor":"cato",...}
```

Expected post-Pipeline fields may resemble:

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

## 7. Add the demonstration Route

Use:

```text
cribl/routes/cato_events_route.yml
```

The Route filter is:

```javascript
__inputId.startsWith('syslog:') && appname === 'cato-events'
```

Suggested test settings:

| Setting | Demonstration value |
|---|---|
| Route ID | `cato_events_route` |
| Filter | `__inputId.startsWith('syslog:') && appname === 'cato-events'` |
| Pipeline | `cato_normalize` |
| Output | Isolated test Destination |
| Final | Yes |
| Enabled | Yes |

Replace the example output ID:

```text
cato_file_output
```

with an isolated test Destination.

Place the Route before broad catch-all test routes that might consume the event first. Do not insert it into a production route table.

## 8. Use an isolated test Destination

A temporary filesystem or other controlled test Destination can demonstrate Source, Route, Pipeline, and output behavior.

Confirm the Destination:

- Is explicitly approved for the demonstration.
- Is isolated from production analytics, alerting, billing, and automation.
- Is enabled and healthy.
- Has enough capacity for a possible backlog.
- Does not expose test events to unauthorized users or systems.

## 9. Commit and deploy only to the test Worker Group

In a distributed test deployment:

1. Save the Source, Pipeline, Route, and Destination changes.
2. Review the diff.
3. Commit the test configuration.
4. Deploy only to the intended test Worker Group.
5. Confirm the Worker reports the new configuration as active.

A configuration visible in the UI but not deployed is not active. A configuration deployed to the wrong Worker Group can affect unrelated traffic, which is why change review exists despite humanity's repeated attempts to skip it.

## 10. Test connectivity before starting polling

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
  | nc <cribl-test-host> 9514
```

Validate:

- The test Syslog Source receives the event.
- `appname` is `cato-events`.
- `cato_events_route` matches.
- `cato_normalize` runs.
- `event_type` is `Synthetic Test`.
- The isolated test Destination receives the event.

## 12. Start the demonstration poller

```bash
cd /opt/catocribbler/poller
docker compose up -d
docker compose logs -f cato-events-poller
```

A successful test may show:

```text
INFO Fetched=144 Sent=144 marker_len=180
```

## 13. Validate every stage

Do not stop at the poller log.

Confirm:

1. Test Source connection count increases.
2. Test Source received-event count increases.
3. Live Capture shows only approved test records.
4. Demonstration Route match count increases.
5. Demonstration Pipeline adds `cribl_pipeline=cato_normalize`.
6. No unexpected `cato_parse_error` values appear.
7. Isolated test Destination receives events.
8. Queues and storage remain within approved limits.

`Fetched=144 Sent=144` means the poller wrote 144 records to the socket. It does not prove downstream persistence or correctness.

## 14. Common demonstration failures

### Cribl Source receives nothing

Check:

- Correct Docker host address or shared test network.
- TCP port is published or shared-network DNS works.
- Source is enabled and deployed.
- Source listens on TCP rather than only UDP.
- Source address is reachable.
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

Capture only approved test data and confirm `message` contains one complete JSON object.

### Pipeline succeeds but Destination receives nothing

Check:

- Route output ID.
- Destination health and credentials.
- Backpressure and persistent queues.
- Destination-side filters.
- Storage and evaluation-license capacity.

### TCP works but TLS fails

Check:

- Cribl TLS is enabled on the exact test port.
- Poller has `CRIBL_SYSLOG_TLS=true`.
- Server name matches a certificate SAN.
- CA chain is correct.
- Source is not requiring a client certificate.

## 15. Remove the demonstration

When testing ends:

- Stop and remove the poller container.
- Revoke the Cato API key.
- Remove demonstration Cribl objects if they are no longer required.
- Remove the poller from shared Docker networks.
- Remove test files and sensitive data according to policy.

## No support, license, or warranty

No support is provided by Damon Cassell, Cato Networks, Cribl, contributors, employers, vendors, or any other party.

This repository intentionally includes no license grant from the author. All material is provided “AS IS” and “AS AVAILABLE,” without warranty or liability to the maximum extent permitted by law.

Read [`../DISCLAIMER.md`](../DISCLAIMER.md).
