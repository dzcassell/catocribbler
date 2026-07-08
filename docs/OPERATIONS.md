# Operations, upgrades, recovery, and monitoring

This guide covers day-to-day operation of the `cato-events-poller` after it has been integrated with an existing Cribl Stream Docker deployment.

The poller lifecycle is separate from the Cribl lifecycle. Normal poller maintenance should not stop, recreate, upgrade, or remove the customer's Cribl containers.

Run commands from:

```bash
cd /opt/catocribbler/poller
```

## 1. Normal status checks

```bash
docker compose ps
docker compose logs --tail=50 cato-events-poller
```

Expected status:

```text
cato-events-poller   Up ...
```

Healthy logs:

```text
INFO starting marker_len=180
INFO Fetched=144 Sent=144 marker_len=180
```

## 2. Understand what the logs prove

- `Fetched`: records returned by Cato.
- `Sent`: records successfully written to the connected Cribl TCP/TLS socket.
- `marker_len`: length of the current opaque Cato marker.

A matching line such as:

```text
Fetched=144 Sent=144
```

proves successful socket delivery of that page. It does not by itself prove that the existing Cribl Route, Pipeline, or Destination processed the records successfully.

Operational monitoring must cover both sides:

### Poller

- Container running state.
- Time since the last successful page.
- Repeated API errors.
- Repeated network or TLS errors.
- Marker presence and update activity.

### Existing Cribl deployment

- Syslog Source connection and event counts.
- Route match counts.
- Pipeline parse failures.
- Destination health.
- Persistent queues and backpressure.

## 3. Start, stop, restart, and recreate only the poller

Start:

```bash
docker compose up -d
```

Stop:

```bash
docker compose stop cato-events-poller
```

Restart:

```bash
docker compose restart cato-events-poller
```

Recreate:

```bash
docker compose up -d --force-recreate cato-events-poller
```

Remove the poller container and its private Compose network while preserving local secrets and state:

```bash
docker compose down
```

These commands do not operate on the customer's existing Cribl Compose project unless someone has combined the projects manually.

## 4. Marker management

The marker file is:

```text
state/marker.txt
```

Check metadata without displaying the value:

```bash
ls -l state/marker.txt
wc -c state/marker.txt
sha256sum state/marker.txt
```

The poller advances the marker only after the page has been written successfully to Cribl's socket.

The marker prevents unnecessary replay. Preserve it during:

- Poller upgrades.
- Host migrations.
- Container rebuilds.
- API-key rotation.
- Changes to the Cribl connection method.

Do not share one marker directory between multiple active pollers.

## 5. Backup

Back up:

- `.env`
- `state/marker.txt`
- Cribl CA chain
- API-key reference or protected key file according to policy
- Git commit SHA
- Any `compose.override.yaml` that attaches the poller to the existing Cribl network

Example protected backup:

```bash
umask 077
BACKUP="/root/catocribbler-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"

cp -a .env "$BACKUP/"
cp -a secrets "$BACKUP/"
cp -a state "$BACKUP/"
test -e compose.override.yaml && cp -a compose.override.yaml "$BACKUP/"
git -C /opt/catocribbler rev-parse HEAD > "$BACKUP/git-commit.txt"

chmod -R go-rwx "$BACKUP"
echo "Backup created: $BACKUP"
```

Do not back up or alter the existing Cribl deployment as part of routine poller maintenance unless the change plan also modifies Cribl configuration.

## 6. Upgrade the poller code

Review changes first:

```bash
cd /opt/catocribbler
CURRENT_COMMIT="$(git rev-parse HEAD)"
echo "Current commit: $CURRENT_COMMIT"

git fetch origin
git log --oneline --decorate HEAD..origin/main
git diff --stat HEAD..origin/main
```

Back up marker state:

```bash
cp -a \
  poller/state/marker.txt \
  "/root/cato-marker-before-upgrade-$(date +%Y%m%d-%H%M%S).txt"
```

After approval:

```bash
git pull --ff-only
cd poller

docker compose config
docker compose build --pull --no-cache
docker compose up -d --force-recreate cato-events-poller
docker compose logs --tail=100 cato-events-poller
```

Confirm:

- Cato API preflight still passes.
- Cribl TCP/TLS preflight still passes.
- Matching `Fetched` and `Sent` counts appear.
- Existing Cribl destination metrics continue increasing.

## 7. Roll back poller code

```bash
cd /opt/catocribbler
git checkout --detach PREVIOUS_COMMIT_SHA
cd poller

docker compose build --no-cache
docker compose up -d --force-recreate cato-events-poller
docker compose logs --tail=100 cato-events-poller
```

Do not restore an older marker unless replay is intentional. Code rollback and queue-state rollback are separate decisions.

## 8. Rotate the Cato API key

For a production integration, use a Service API Key associated with a service principal where possible.

Create and validate the replacement key before revoking the old one.

```bash
umask 077
read -rsp 'New Cato API key: ' CATO_KEY
printf '%s' "$CATO_KEY" > secrets/cato_api_key.new
unset CATO_KEY
printf '\n'

chown 10001 secrets/cato_api_key.new
chmod 0400 secrets/cato_api_key.new
mv secrets/cato_api_key.new secrets/cato_api_key

docker compose up -d --force-recreate cato-events-poller
docker compose logs --tail=100 cato-events-poller
```

Run the Cato authentication checks in [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md) and confirm a successful page before revoking the old key.

## 9. Change the Cato account or API endpoint

Changing the account or endpoint changes the queue context.

```dotenv
CATO_ACCOUNT_ID=...
CATO_API_URL=...
```

Do not reuse the previous account's marker.

```bash
docker compose stop cato-events-poller
mv state/marker.txt "state/marker.previous-account.$(date +%Y%m%d-%H%M%S)"
nano .env
docker compose up -d cato-events-poller
```

Expect a backlog for the new account.

## 10. Change how the poller reaches the existing Cribl container

Typical reasons:

- Moving from Docker host published port to shared Docker network.
- Changing Cribl Worker or VIP.
- Enabling TLS.
- Changing the Syslog Source port.

Update `.env` and, if required, `compose.override.yaml`.

Then test before recreating the continuous poller:

1. Cribl TCP preflight.
2. Cribl TLS preflight when enabled.
3. Synthetic syslog event.
4. Existing Route/Pipeline/Destination delivery.

Only then run:

```bash
docker compose up -d --force-recreate cato-events-poller
```

## 11. Intentionally reset the marker

Resetting the marker can replay the currently retained EventsFeed queue and create duplicates.

```bash
docker compose stop cato-events-poller
mv state/marker.txt "state/marker.before-reset.$(date +%Y%m%d-%H%M%S)"
docker compose up -d cato-events-poller
```

Coordinate with Cribl and downstream owners before doing this.

## 12. Verify hardening

```bash
docker inspect cato-events-poller --format '
User={{.Config.User}}
ReadonlyRootfs={{.HostConfig.ReadonlyRootfs}}
SecurityOpt={{json .HostConfig.SecurityOpt}}
RestartPolicy={{.HostConfig.RestartPolicy.Name}}
Networks={{json .NetworkSettings.Networks}}
'
```

Expected values include:

```text
User=10001
ReadonlyRootfs=true
SecurityOpt=["no-new-privileges:true"]
RestartPolicy=unless-stopped
```

## 13. Monitoring recommendations

Alert on:

- Poller container not running.
- No successful poll within an expected time window.
- Consecutive HTTP 401, 403, 422, or 429 responses.
- DNS, connection, or TLS errors.
- Repeated full 3,000-record pages.
- Marker missing or state directory unwritable.
- Existing Cribl Source receiving no events while Cato reports non-zero fetched counts.
- Route or Pipeline error increases.
- Destination backpressure or persistent queue growth.
- API-key expiration.
- Cribl TLS certificate expiration.

## 14. Troubleshooting

Use [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md) as the primary diagnostic guide.

It contains separate procedures for:

- Creating Admin and Service API Keys.
- Authenticating directly to the Cato endpoint.
- Interpreting Cato HTTP errors.
- Discovering existing Cribl Docker ports and networks.
- Testing host-published-port and shared-network connectivity.
- Testing TLS.
- Sending a synthetic event.
- Validating Source, Route, Pipeline, and Destination stages.
- Repairing secret and marker permissions.
- Collecting safe diagnostics.

## 15. Decommission the poller

Stop and remove only the poller:

```bash
cd /opt/catocribbler/poller
docker compose down
```

Archive the marker and approved configuration according to policy, then remove or revoke the Cato key.

Do not remove the existing Cribl containers or their data volumes as part of poller decommissioning.

## Related documentation

- [`INSTALL.md`](INSTALL.md): installation beside existing Cribl containers.
- [`CRIBL.md`](CRIBL.md): existing Cribl integration.
- [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md): full diagnostic procedures.
- [`../SECURITY.md`](../SECURITY.md): security guidance.
