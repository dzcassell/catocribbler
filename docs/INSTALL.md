# Fresh customer installation

> [!CAUTION]
> **UNSUPPORTED, NON-PRODUCTION DEMONSTRATION ONLY.** This repository is not supported, approved, endorsed, maintained, or warranted by Damon Cassell, Cato Networks, Cribl, any employer, contributor, vendor, partner, or anyone else. There is no license grant. Do not use this code in production. Read [`../DISCLAIMER.md`](../DISCLAIMER.md).

## 1. Before starting

Confirm the customer has:

### Cato

- Numeric Cato account ID
- Fresh Service API Key with read-only permissions
- Approval to use EventsFeed for this demonstration

### Cribl

- Running non-production Cribl Worker or single-instance container
- Enabled TCP Syslog Source, normally on port `9514`
- Test Route and Pipeline
- Isolated test Destination

### Linux host

- Docker Engine
- Docker Compose v2
- Git
- Python 3
- `curl`
- Interactive terminal access

Check the host:

```bash
docker version
docker compose version
git --version
python3 --version
curl --version
```

## 2. Run one command

```bash
curl -fsSL https://raw.githubusercontent.com/dzcassell/catocribbler/main/install.sh | sudo bash
```

That is the complete launch sequence. The customer does not need to know a Git commit, SHA, branch-ref syntax, or any other ritual from the software archaeology department.

## 3. Answer the prompts

The normal installation looks like this:

1. Type:

   ```text
   I UNDERSTAND
   ```

2. Press Enter to accept the installation directory:

   ```text
   /opt/cribbler
   ```

3. Press Enter to accept the default API endpoint, or enter the tenant endpoint provided by Cato:

   ```text
   https://api.catonetworks.com/api/v1/graphql
   ```

4. Enter the numeric Cato account ID.
5. Review the automatically detected Cribl container and endpoint.
6. Press Enter to accept the detected Cribl listener when it is correct.
7. Answer whether the Cribl Syslog connection uses TLS.
8. Press Enter to accept the 30-second polling interval.
9. Paste the Cato API key twice. It is not displayed.
10. Press Enter to create the installation.
11. Press Enter to send one synthetic event.
12. Validate the synthetic event in Cribl.
13. Type `START` to begin continuous polling, or press Enter to leave it stopped.

## 4. Automatic Cribl detection

The installer normally finds a running Cribl container publishing `9514/tcp` and displays something like:

```text
The installer found a running Cribl container with a published Syslog listener:

  Cribl container:            cribl-worker
  Docker port mapping:        0.0.0.0:9514
  Address the poller will use: 192.168.40.15:9514

Use this detected Cribl listener [Y/n]:
```

Press Enter when the detected container and address are correct.

The installer asks for manual networking details only when:

- No running `cribl*` container publishes `9514/tcp`, or
- The detected listener is not the intended listener.

## 5. Expected preflight results

The installer first validates Cato without sending events to Cribl or writing the marker:

```text
CATO API PREFLIGHT PASS fetched=N decoded=N current_marker_len=0 returned_marker_len=N
```

It then validates the Cribl connection:

```text
CRIBL CONNECTION PREFLIGHT PASS host=<host> port=9514 tls=<true-or-false> peer=<address>
```

When the synthetic test is enabled:

```text
SYNTHETIC CRIBL EVENT SENT
```

## 6. Validate the synthetic event in Cribl

Confirm:

1. The Syslog Source received the event.
2. `appname` is `cato-events`.
3. The JSON payload contains:

   ```text
   event_type=Catocribbler Installer Synthetic Test
   ```

4. Route `cato_events_route` matched.
5. Pipeline `cato_normalize` ran.
6. The isolated test Destination received the event.

Only then type:

```text
START
```

## 7. First-run warning

A new installation has no EventsFeed marker. Starting continuous polling can retrieve all currently retained EventsFeed records in consecutive pages of up to 3,000.

Pressing Enter at the final prompt leaves the installation built and tested but stopped.

## 8. Validate the running installation

```bash
cd /opt/cribbler/poller

docker compose ps
docker compose logs --tail=100 cato-events-poller

stat -c 'uid=%u gid=%g mode=%a size=%s path=%n' \
  .env \
  secrets \
  secrets/cato_api_key \
  secrets/cribl_ca.pem \
  state \
  state/marker.txt 2>/dev/null || true
```

Successful polling resembles:

```text
INFO starting marker_len=0
INFO Fetched=25 Sent=25 marker_len=180
```

or, when no events are available:

```text
INFO Fetched=0 Sent=0 marker_len=180
```

`Fetched=N Sent=N` proves that the poller wrote the page to the Cribl socket. It does not prove downstream parsing, routing, persistence, or Destination delivery.

## 9. Installation files

Default installation path:

```text
/opt/cribbler
```

API key:

```text
/opt/cribbler/poller/secrets/cato_api_key
```

Marker state:

```text
/opt/cribbler/poller/state/marker.txt
```

Non-secret installation information:

```text
/opt/cribbler/INSTALLATION_INFO.txt
```

The installer records the exact installed Git commit automatically. The customer does not select or enter it.

## 10. Useful commands

```bash
cd /opt/cribbler/poller
```

Status:

```bash
docker compose ps
```

Logs:

```bash
docker compose logs -f cato-events-poller
```

Stop:

```bash
docker compose stop cato-events-poller
```

Start:

```bash
docker compose up -d
```

Remove the poller container while preserving local files:

```bash
docker compose down
```

## 11. Cleanup after the demonstration

```bash
cd /opt/cribbler/poller
docker compose down
```

Then:

1. Revoke the Cato Service API Key.
2. Remove the demonstration Service Principal when no longer needed.
3. Remove test-only Cribl configuration when appropriate.
4. Remove copied credentials, marker state, and test data according to policy.
5. Remove the installation directory:

   ```bash
   rm -rf -- /opt/cribbler
   ```
