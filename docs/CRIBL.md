# Cribl Stream configuration

This guide configures Cribl Stream to receive the RFC 5424 syslog records emitted by `cato-events-poller`, parse the JSON payload, and route the resulting events to a Destination.

Cribl menu names and deployment controls can vary by version and topology. The required logical settings are listed explicitly so they can be applied in the UI or through normal Cribl configuration management.

## Data flow

```text
cato-events-poller
    |
    | RFC 5424 syslog over TCP or TLS
    v
Cribl Syslog Source: in_syslog
    |
    v
Route: cato_events_route
    |
    v
Pipeline: cato_normalize
    |
    v
Validation or production Destination
```

## 1. Select the Worker Group

In a distributed Cribl deployment, make all Source, Pipeline, Route, and Destination changes in the Worker Group that will receive the Cato traffic.

The poller must connect to a Worker, load balancer, or virtual IP that sends traffic to that Worker Group. It normally should not send syslog to the Leader management port.

## 2. Create the Syslog Source

Create a Syslog Source with these baseline settings:

| Setting | Recommended value |
|---|---|
| Source type | Syslog |
| Source ID | `in_syslog` |
| Protocol | TCP or TLS over TCP |
| Port | `9514` |
| Enabled | Yes |

The supplied Route assumes the Source ID is `in_syslog` because Cribl identifies events from that source with an input ID beginning with:

```text
syslog:in_syslog
```

If a different Source ID is used, update the Route filter accordingly.

### Listener address and firewall

Confirm that:

- The Source listens on an address reachable from the Docker host.
- TCP port `9514`, or the selected alternative, is allowed through host and network firewalls.
- A container can connect to the advertised hostname or IP address.
- A load balancer preserves a stable TCP path long enough for each page to be transmitted.

The poller opens a TCP connection for each non-empty EventsFeed page and sends all events in that page over the connection.

## 3. Configure TLS when used

For production, enable TLS on the Cribl Syslog Source.

The Cribl certificate must:

- Be valid for the DNS name configured as `CRIBL_SYSLOG_SERVER_NAME`.
- Be within its validity period.
- Include any required intermediate certificates in the served chain.
- Be trusted by the CA file mounted into the poller as `/run/secrets/cribl_ca.pem`.

Corresponding poller settings:

```dotenv
CRIBL_SYSLOG_TLS=true
CRIBL_SYSLOG_HOST=cribl-worker.example.com
CRIBL_SYSLOG_SERVER_NAME=cribl-worker.example.com
CRIBL_SYSLOG_CA_FILE=/run/secrets/cribl_ca.pem
```

For a non-TLS lab Source:

```dotenv
CRIBL_SYSLOG_TLS=false
```

The connection setting must match on both sides. Enabling TLS on only one side produces immediate connection or handshake failures, because computers remain stubbornly literal.

## 4. Create a validation Destination

Before routing to a production SIEM or data lake, create a simple validation Destination.

A filesystem Destination is useful in a lab because it proves that events passed through the Source, Route, and Pipeline. Example Destination ID:

```text
cato_file_output
```

Choose a path that is writable by the Cribl Worker and has enough capacity for an initial backlog.

After validation, replace `cato_file_output` with the intended production Destination ID, such as a SIEM, object store, Kafka, or another supported target.

## 5. Create the `cato_normalize` Pipeline

The supplied Pipeline configuration is:

```text
cribl/pipelines/cato_normalize/conf.yml
```

Create a Pipeline with ID:

```text
cato_normalize
```

Then reproduce or deploy the configuration from the supplied file.

The Pipeline performs these actions:

1. Reads the JSON payload from the syslog `message` field.
2. Verifies that the payload is a JSON object.
3. Promotes all JSON properties to top-level Cribl event fields.
4. Adds:
   - `cribl_pipeline=cato_normalize`
   - `vendor=cato` when absent
   - `product=cato_sase` when absent
5. Converts a numeric Cato `time` value to Cribl `_time` when possible.
6. Stores the normalized JSON in `_raw`.
7. Removes the original `message` field.
8. Adds `cato_parse_error` and marks the pipeline as failed if parsing raises an exception.

### Expected input before the Pipeline

Cribl's Syslog Source should parse the RFC 5424 envelope and expose fields similar to:

```text
appname = cato-events
host = cato-events-poller
message = {"time":...,"event_type":...,"vendor":"cato",...}
```

### Expected output after the Pipeline

The JSON payload should be promoted, for example:

```json
{
  "appname": "cato-events",
  "host": "cato-events-poller",
  "event_type": "Security",
  "event_sub_type": "Anti Malware",
  "account_id": "12345",
  "vendor": "cato",
  "product": "cato_sase",
  "cribl_pipeline": "cato_normalize"
}
```

The exact Cato event fields vary by event type.

## 6. Create the Route

The supplied Route example is:

```text
cribl/routes/cato_events_route.yml
```

Create a Route with these values:

| Setting | Value |
|---|---|
| Route ID | `cato_events_route` |
| Name | `cato_events_route` |
| Filter | `__inputId.startsWith('syslog:in_syslog') && appname === 'cato-events'` |
| Pipeline | `cato_normalize` |
| Output | `cato_file_output` or the selected production Destination |
| Final | Yes |
| Enabled | Yes |

The `appname` value is set by the poller in the RFC 5424 header and is always:

```text
cato-events
```

### Route ordering

Place the Cato Route before broad catch-all routes that could consume the same Syslog Source traffic.

Because the supplied Route is final, a matching event will not continue to lower Routes after it is sent to the selected output.

## 7. Deploy the Cribl changes

In a distributed deployment:

1. Save the Source, Pipeline, Route, and Destination.
2. Commit the configuration changes.
3. Deploy them to the target Worker Group.
4. Confirm that the Worker reports the new configuration as active.

Do not start the Cato poller while the Route exists only as an undeployed draft. The poller will happily send data into whatever configuration is actually running, not the configuration someone intended to deploy later.

## 8. Validate the Source before starting the poller

Confirm that the listener is active on the Worker host.

From the Docker host, test TCP connectivity:

```bash
nc -vz CRIBL_HOST 9514
```

Or use the poller image after `.env` has been configured:

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

with socket.create_connection((host, port), timeout=5):
    print(f"CRIBL TCP PREFLIGHT PASS host={host} port={port}")
'
```

A TCP preflight does not prove that TLS, routing, parsing, or destination delivery is correct.

## 9. Start the poller and validate live events

Start the poller:

```bash
cd /opt/catocribbler/poller
docker compose up -d
docker compose logs -f cato-events-poller
```

Look for matching counts:

```text
INFO Fetched=144 Sent=144 marker_len=180
```

In Cribl, verify:

- The Syslog Source's received event count increases.
- Live capture or preview shows `appname=cato-events`.
- The Cato Route matches the events.
- The `cato_normalize` Pipeline runs.
- `cribl_pipeline` is `cato_normalize`.
- `vendor` is `cato`.
- `product` is `cato_sase`.
- `message` has been removed after successful parsing.
- `_raw` contains normalized JSON.
- The Destination's delivered event count increases.

## 10. Validate with a synthetic syslog record

This test validates the Cribl Source, Route, Pipeline, and Destination without calling Cato.

From a host that can reach the Source:

```bash
printf '<134>1 2026-01-01T00:00:00.000Z test-host cato-events - - - {"time":1767225600000,"event_type":"Synthetic Test","vendor":"cato","product":"cato_sase"}\n' \
  | nc CRIBL_HOST 9514
```

For a TLS Source, use a TLS-capable client and the appropriate CA verification rather than plain `nc`.

The synthetic event should:

- Match `cato_events_route`.
- Pass through `cato_normalize`.
- Reach the configured Destination.
- Contain `event_type=Synthetic Test`.

## 11. Troubleshooting Cribl ingestion

### The poller logs `Sent=N`, but Cribl shows nothing

Check:

- The poller is connecting to the correct Worker, VIP, and port.
- The Source is enabled and deployed.
- The protocol matches: TCP versus TLS.
- Host and network firewalls permit the connection.
- The event is not being captured by an earlier Route.
- The supplied Route filter matches the actual Source ID.

### Source receives events, but the Route does not match

Inspect the incoming event before routing:

- Confirm `appname` equals `cato-events`.
- Confirm `__inputId` begins with `syslog:in_syslog`.
- If the Source ID differs, change the Route filter.

Example alternate filter:

```javascript
__inputId.startsWith('syslog:my_cato_source') && appname === 'cato-events'
```

### Route matches, but parsing fails

Look for:

```text
cato_parse_error
cribl_pipeline=cato_normalize_parse_failed
```

Capture the pre-Pipeline event and confirm that `message` contains one complete JSON object. Do not post production event contents into a public issue because they can contain tenant, user, device, and security data.

### Events parse but do not reach the Destination

Check:

- Destination health and credentials.
- Output ID on the Route.
- Destination backpressure or persistent queue status.
- Any Destination-side filtering.
- Worker disk capacity when using filesystem output or persistent queues.

### TLS handshake failure

Confirm:

- `CRIBL_SYSLOG_TLS=true`.
- The Source is actually using TLS on the configured port.
- `CRIBL_SYSLOG_SERVER_NAME` matches the certificate.
- `secrets/cribl_ca.pem` contains the correct CA chain.
- The certificate and issuing CA are not expired.
- Middleboxes are not replacing the certificate.

## 12. Production checklist

Before changing the Route to a production Destination:

- [ ] Source receives live events.
- [ ] TLS is enabled where required.
- [ ] Route matches only the intended Cato records.
- [ ] Pipeline parses representative Cato event types.
- [ ] No unexpected `cato_parse_error` fields are present.
- [ ] Destination delivery is confirmed.
- [ ] Initial backlog volume has been estimated.
- [ ] Destination and Cribl licensing/capacity can handle the rate.
- [ ] Monitoring exists for Source, Route, Pipeline errors, and Destination health.
- [ ] The Cato marker is backed up as part of deployment-state backup.

## Related documentation

- [`INSTALL.md`](INSTALL.md): poller installation and Cato configuration.
- [`OPERATIONS.md`](OPERATIONS.md): upgrades, backup, recovery, and troubleshooting.
- [`../cribl/pipelines/cato_normalize/conf.yml`](../cribl/pipelines/cato_normalize/conf.yml): supplied Pipeline configuration.
- [`../cribl/routes/cato_events_route.yml`](../cribl/routes/cato_events_route.yml): supplied Route example.
