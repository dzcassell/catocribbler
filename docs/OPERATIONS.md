# Operations, upgrades, recovery, and troubleshooting

This guide covers day-to-day operation of the `cato-events-poller` container after installation.

Run operational commands from the deployment directory unless a command says otherwise:

```bash
cd /opt/catocribbler/poller
```

## 1. Normal status checks

Check container status:

```bash
docker compose ps
```

Expected result:

```text
NAME                 STATUS
cato-events-poller   Up ...
```

Check recent logs:

```bash
docker compose logs --tail=50 cato-events-poller
```

Follow logs continuously:

```bash
docker compose logs -f cato-events-poller
```

## 2. Understanding poller logs

### Startup

```text
INFO starting marker_len=180
```

This confirms that the marker was loaded. The marker is opaque; its length is logged only as a basic state signal.

### Successful page

```text
INFO Fetched=144 Sent=144 marker_len=180
```

- `Fetched`: records returned by Cato.
- `Sent`: normalized syslog records written to the Cribl TCP connection.
- `marker_len`: length of the current marker after the page was processed.

For a healthy page, `Fetched` and `Sent` should match.

### No new events

```text
INFO Fetched=0 Sent=0 marker_len=180
```

This is successful and means no new events were available.

### Full backlog page

```text
INFO Fetched=3000 Sent=3000 marker_len=180
```

A full 3,000-event page causes the poller to immediately request another page rather than waiting for the normal polling interval. Repeated full pages usually indicate an initial backlog or sustained high volume.

### Poll failure

```text
ERROR poll failed
Traceback ...
```

The poller waits for the configured interval and tries again. The marker is not advanced for a failed page.

## 3. Start, stop, restart, and recreate

Start:

```bash
docker compose up -d
```

Stop without deleting local state:

```bash
docker compose stop
```

Restart:

```bash
docker compose restart cato-events-poller
```

Recreate the container while keeping `.env`, secrets, and marker state:

```bash
docker compose up -d --force-recreate
```

Stop and remove the Compose container and network:

```bash
docker compose down
```

`docker compose down` does not delete the bind-mounted `state/` directory or local secret files.

## 4. Marker management

The marker file is:

```text
poller/state/marker.txt
```

It represents the position in Cato's EventsFeed queue.

Check it without displaying its contents:

```bash
ls -l state/marker.txt
wc -c state/marker.txt
sha256sum state/marker.txt
```

The poller writes the next marker only after all events in the page have been sent to Cribl.

Preserving the marker prevents:

- Replaying the available queue after a rebuild.
- Duplicate event ingestion during migration.
- A large and unexpected initial backlog.

Marker updates use a temporary file and atomic replacement. UID `10001` must therefore be able to create and rename files in `state/`, not merely modify the existing marker.

Do not share one state directory between active pollers. Two writers can produce duplicates, gaps, or marker regression.

## 5. Backup

Back up these items together:

- `.env`
- `secrets/cato_api_key`, preferably through the approved secret manager
- `secrets/cribl_ca.pem`
- `state/marker.txt`
- The Git commit SHA in use

Create a protected local backup:

```bash
cd /opt/catocribbler/poller
umask 077
BACKUP="/root/catocribbler-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"

cp -a .env "$BACKUP/"
cp -a secrets "$BACKUP/"
cp -a state "$BACKUP/"
git rev-parse HEAD > "$BACKUP/git-commit.txt"

chmod -R go-rwx "$BACKUP"
echo "Backup created: $BACKUP"
```

In stricter environments, back up only the marker and configuration references, then retrieve the API key again from the secret manager during recovery.

## 6. Upgrade from GitHub

Recommended change-controlled sequence:

1. Record the current commit.
2. Back up the marker and runtime configuration.
3. Fetch the new code.
4. Review the changes.
5. Build the new image while the current container is still running.
6. Recreate the container.
7. Confirm a successful polling cycle.

Review the proposed update:

```bash
cd /opt/catocribbler

CURRENT_COMMIT="$(git rev-parse HEAD)"
echo "Current commit: $CURRENT_COMMIT"

cp -a poller/state/marker.txt "/root/cato-marker-before-upgrade-$(date +%Y%m%d-%H%M%S).txt"

git fetch origin
git log --oneline --decorate HEAD..origin/main
git diff --stat HEAD..origin/main
```

After approval:

```bash
git pull --ff-only
cd poller

docker compose config
docker compose build --pull --no-cache
docker compose up -d --force-recreate
docker compose logs --tail=50 cato-events-poller
```

Confirm a line similar to:

```text
INFO Fetched=27 Sent=27 marker_len=180
```

### Pin a specific commit

```bash
cd /opt/catocribbler
git fetch origin
git checkout --detach COMMIT_SHA
cd poller
docker compose build --pull --no-cache
docker compose up -d --force-recreate
```

Record the selected SHA in the change record.

## 7. Roll back code

If a new version fails but the existing marker and configuration remain intact:

```bash
cd /opt/catocribbler
git checkout --detach PREVIOUS_COMMIT_SHA
cd poller
docker compose build --no-cache
docker compose up -d --force-recreate
docker compose logs --tail=100 cato-events-poller
```

Do not restore an older marker unless intentionally replaying events. Rolling back code and rolling back queue state are separate operations.

## 8. Rotate the Cato API key

Create the replacement key in Cato first. Then replace the local secret without placing it in shell history:

```bash
cd /opt/catocribbler/poller
umask 077

read -rsp "New Cato API key: " CATO_KEY
printf '%s' "$CATO_KEY" > secrets/cato_api_key.new
unset CATO_KEY
printf '\n'

chown 10001 secrets/cato_api_key.new
chmod 0400 secrets/cato_api_key.new
mv secrets/cato_api_key.new secrets/cato_api_key

docker compose up -d --force-recreate
docker compose logs --tail=50 cato-events-poller
```

After a successful poll, revoke the old key according to organizational procedure.

Do not revoke the old key before validating the replacement unless an active credential compromise requires immediate revocation.

## 9. Change the Cato account or API endpoint

Changing either value changes the source tenant context:

```dotenv
CATO_ACCOUNT_ID=...
CATO_API_URL=...
```

Do not reuse the previous tenant's marker for a different account or regional endpoint.

Safe procedure:

```bash
docker compose stop
mv state/marker.txt "state/marker.previous-tenant.$(date +%Y%m%d-%H%M%S)"
nano .env
docker compose up -d --force-recreate
```

Expect an initial backlog for the new tenant.

## 10. Change the Cribl listener

Update these values in `.env`:

```dotenv
CRIBL_SYSLOG_HOST=...
CRIBL_SYSLOG_PORT=...
CRIBL_SYSLOG_TLS=...
CRIBL_SYSLOG_SERVER_NAME=...
```

Then recreate the container:

```bash
docker compose up -d --force-recreate
```

Test connectivity before cutover when possible.

## 11. Intentionally reset the marker

Resetting the marker can replay the available EventsFeed queue and create duplicates downstream.

Only do this when replay is explicitly required:

```bash
cd /opt/catocribbler/poller
docker compose stop
mv state/marker.txt "state/marker.before-reset.$(date +%Y%m%d-%H%M%S)"
docker compose up -d
docker compose logs -f cato-events-poller
```

An empty state starts from the beginning of the currently available EventsFeed queue, not necessarily from the beginning of the tenant's history.

## 12. Verify container hardening

```bash
docker inspect cato-events-poller --format '
User={{.Config.User}}
ReadonlyRootfs={{.HostConfig.ReadonlyRootfs}}
SecurityOpt={{json .HostConfig.SecurityOpt}}
RestartPolicy={{.HostConfig.RestartPolicy.Name}}
'
```

Expected values include:

```text
User=10001
ReadonlyRootfs=true
SecurityOpt=["no-new-privileges:true"]
RestartPolicy=unless-stopped
```

## 13. Troubleshooting

### Required environment variable is missing

Cause: `.env` is missing, malformed, or lacks a required variable.

```bash
ls -l .env
docker compose config
```

Required variables:

- `CATO_API_URL`
- `CATO_ACCOUNT_ID`
- `CATO_API_KEY_FILE`
- `CRIBL_SYSLOG_HOST`

### Cato API key file is empty or unreadable

```bash
test -s secrets/cato_api_key && echo present
wc -c secrets/cato_api_key
stat -c 'owner_uid=%u mode=%a path=%n' secrets/cato_api_key
sudo -u '#10001' test -r secrets/cato_api_key && echo readable
```

Expected owner UID is `10001` and recommended mode is `400`. Do not display the key.

### HTTP 401 or 403 from Cato

Likely causes:

- Invalid, expired, or revoked API key.
- API key lacks EventsFeed permission.
- Source-IP restriction excludes the Docker host's public egress address.
- The key belongs to a different tenant.

### HTTP 422 from Cato

Likely causes:

- Incorrect API endpoint.
- GraphQL schema mismatch after an API change.
- Invalid account ID format.
- Request variables rejected by the tenant endpoint.

The poller includes the response body in the error text, truncated to a practical operational length. Review it for the specific GraphQL error without posting tenant data publicly.

### Fetched and Sent do not match

This should not occur during a healthy cycle. Possible causes:

- A record could not be normalized.
- A connection failed partway through the page.
- The process was interrupted.

The marker should not advance for a failed page. Review the traceback and verify Cribl connectivity.

### Connection refused

Likely causes:

- Incorrect Cribl host or port.
- Cribl Source not enabled or deployed.
- Firewall rejection.
- Listener bound to another interface.
- `127.0.0.1` used while Cribl is outside the container.

### Connection timeout

Likely causes:

- Routing or firewall drop.
- Wrong IP address.
- Load balancer not forwarding the port.
- DNS resolving to an unreachable address.

Use the container preflight in [`INSTALL.md`](INSTALL.md).

### TLS certificate verification failure

Check:

- `CRIBL_SYSLOG_TLS=true`.
- The Source uses TLS on the selected port.
- `secrets/cribl_ca.pem` contains the correct CA chain.
- `CRIBL_SYSLOG_SERVER_NAME` matches the certificate SAN.
- The server and CA certificates are valid and unexpired.

### Permission denied for `/state/marker.txt`

```bash
cd /opt/catocribbler/poller
chown 10001 state
chmod 0700 state

if test -e state/marker.txt; then
  chown 10001 state/marker.txt
  chmod 0600 state/marker.txt
fi
```

Directory write permission is required because marker updates use atomic replacement.

### Permission denied for `/app/poller.py`

Rebuild from the current Dockerfile, which explicitly makes the script readable and executable by the non-root runtime user:

```bash
docker compose build --no-cache
docker compose up -d --force-recreate
```

### Container repeatedly restarts

```bash
docker compose ps
docker compose logs --tail=200 cato-events-poller
docker inspect cato-events-poller --format '{{.State.ExitCode}} {{.State.Error}}'
```

### Poller is healthy but Cribl receives no events

`Fetched=0 Sent=0` means there were no new events to send.

For non-zero sends, check the Cribl Source, Route, Pipeline, and Destination using [`CRIBL.md`](CRIBL.md).

### Marker never appears

The marker is written only when Cato returns a next marker different from the current one. Check API failures and state-directory permissions.

### First run generates excessive volume

An empty marker retrieves the currently retained queue. Options:

- Allow the backlog to drain.
- Stop the poller and restore a known-good marker from the previous integration.
- Coordinate with downstream owners before restarting.

Do not invent or manually edit a marker.

## 14. Operational monitoring recommendations

Monitor at least:

- Container running state and restart count.
- Time since the last successful `Fetched=N Sent=N` log.
- Repeated poll failures.
- Repeated full 3,000-event pages.
- Cribl Source received events.
- Cribl Route and Pipeline errors.
- Destination delivery health and backpressure.
- State-directory disk availability.
- API-key expiration date.
- TLS certificate expiration date.

## 15. Decommission

Stop ingestion while preserving state:

```bash
cd /opt/catocribbler/poller
docker compose down
```

Archive the marker and approved configuration according to retention policy, then remove secrets using the organization's approved secure-deletion process.

## Related documentation

- [`INSTALL.md`](INSTALL.md): installation and tenant configuration.
- [`CRIBL.md`](CRIBL.md): Cribl Source, Route, Pipeline, and Destination setup.
- [`../SECURITY.md`](../SECURITY.md): security guidance.
