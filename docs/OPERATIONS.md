# Demonstration lifecycle, backup, cleanup, and monitoring

> [!CAUTION]
> **UNSUPPORTED, NON-PRODUCTION DEMONSTRATION ONLY.** This repository is not supported by Damon Cassell, Cato Networks, Cribl, any employer, contributor, vendor, partner, or anyone else. There is no license grant, no warranty, no maintenance promise, no security-update commitment, and no obligation to assist. Do not operate this code as a production service. Read [`../DISCLAIMER.md`](../DISCLAIMER.md).

This guide describes limited lifecycle tasks for an isolated evaluation of `cato-events-poller` beside an existing non-production Cribl Stream Docker deployment.

The commands are examples, not a supported runbook. Independently review every command before execution. The code may lose, duplicate, delay, expose, or replay events and may stop working without notice.

Run commands from:

```bash
cd /opt/catocribbler/poller
```

## 1. Demonstration status checks

```bash
docker compose ps
docker compose logs --tail=50 cato-events-poller
```

A running demonstration may show:

```text
cato-events-poller   Up ...
```

and:

```text
INFO starting marker_len=180
INFO Fetched=144 Sent=144 marker_len=180
```

These messages are not a health certification.

## 2. Understand what the logs do and do not prove

- `Fetched`: records returned by Cato.
- `Sent`: records written to the connected Cribl TCP/TLS socket.
- `marker_len`: length of the current opaque Cato marker.

A matching line such as:

```text
Fetched=144 Sent=144
```

indicates that the demonstration poller wrote the page to the socket without reporting an exception. It does **not** prove:

- Cribl parsed the RFC 5424 record correctly.
- The Route matched.
- The Pipeline transformed the event correctly.
- The Destination persisted the event.
- No duplication, loss, reordering, exposure, or downstream failure occurred.

Validate every stage independently in the test Cribl environment.

## 3. Start, stop, restart, and remove only the demonstration poller

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

Remove the poller container and its private Compose network while preserving local files:

```bash
docker compose down
```

These commands should not operate on the existing Cribl Compose project. Verify the active directory and Compose project name before running them, because Docker will faithfully obey mistakes with admirable efficiency.

## 4. Marker state

The demonstration marker is stored at:

```text
state/marker.txt
```

Check metadata without printing the value:

```bash
ls -l state/marker.txt
wc -c state/marker.txt
sha256sum state/marker.txt
```

The poller attempts to advance the marker after writing a page to the Cribl socket.

Preserve it during a controlled demonstration if you need continuity across:

- Image rebuilds.
- Container recreation.
- API-key rotation.
- Test-host restart.
- Changes to the Cribl connection method.

Do not:

- Share one marker directory between active pollers.
- Edit the marker manually.
- Assume a fixed marker length.
- Treat marker preservation as proof that no events were lost or duplicated.

## 5. Demonstration backup

Back up only what the approved test plan requires:

- `.env`
- `state/marker.txt`
- Cribl CA chain
- API-key reference or protected key file
- Git commit SHA
- `compose.override.yaml`, if used

Example protected backup:

```bash
umask 077
BACKUP="/root/catocribbler-demo-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"

cp -a .env "$BACKUP/"
cp -a secrets "$BACKUP/"
cp -a state "$BACKUP/"
test -e compose.override.yaml && cp -a compose.override.yaml "$BACKUP/"
git -C /opt/catocribbler rev-parse HEAD > "$BACKUP/git-commit.txt"

chmod -R go-rwx "$BACKUP"
echo "Backup created: $BACKUP"
```

This backup can contain credentials, certificates, tenant identifiers, and event state. Protect and destroy it according to the approved test plan.

## 6. Evaluate a newer repository commit

There is no supported upgrade path, compatibility promise, release process, or maintenance schedule.

Before evaluating another commit:

```bash
cd /opt/catocribbler
CURRENT_COMMIT="$(git rev-parse HEAD)"
echo "Current commit: $CURRENT_COMMIT"

git fetch origin
git log --oneline --decorate HEAD..origin/main
git diff --stat HEAD..origin/main
```

Back up demonstration marker state if continuity matters:

```bash
cp -a \
  poller/state/marker.txt \
  "/root/cato-marker-before-demo-update-$(date +%Y%m%d-%H%M%S).txt"
```

After independent review:

```bash
git pull --ff-only
cd poller

docker compose config
docker compose build --pull --no-cache
docker compose up -d --force-recreate cato-events-poller
docker compose logs --tail=100 cato-events-poller
```

Re-run all Cato, TCP/TLS, synthetic-event, Route, Pipeline, and Destination tests. A newer commit can be less functional or less secure than the previous one.

## 7. Return to a previous commit

There is no supported rollback process. For an isolated demonstration, you may attempt:

```bash
cd /opt/catocribbler
git checkout --detach PREVIOUS_COMMIT_SHA
cd poller

docker compose build --no-cache
docker compose up -d --force-recreate cato-events-poller
docker compose logs --tail=100 cato-events-poller
```

Do not restore an older marker unless replay is intentional and approved. Code state and queue state are separate risks.

## 8. Rotate the demonstration Cato API key

Use a short-lived, minimally scoped key. Revoke it when the evaluation ends.

Create and test the replacement before revoking the old key unless an exposure requires immediate revocation:

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

Run the authentication checks in [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md).

## 9. Change the test account or API endpoint

Changing the account or endpoint changes the EventsFeed context.

```dotenv
CATO_ACCOUNT_ID=...
CATO_API_URL=...
```

Do not reuse the previous account's marker:

```bash
docker compose stop cato-events-poller
mv state/marker.txt "state/marker.previous-test-account.$(date +%Y%m%d-%H%M%S)"
nano .env
docker compose up -d cato-events-poller
```

A new account can produce a large backlog. Use only a specifically approved test account.

## 10. Change how the poller reaches Cribl

Typical demonstration changes include:

- Moving between a host-published port and shared Docker test network.
- Changing the test Worker or VIP.
- Enabling TLS.
- Changing the test Syslog Source port.

Update `.env` and, when required, `compose.override.yaml`.

Then run:

1. TCP preflight.
2. TLS preflight when enabled.
3. Synthetic syslog test.
4. Route/Pipeline/Destination validation.

Only then recreate the poller:

```bash
docker compose up -d --force-recreate cato-events-poller
```

## 11. Intentionally reset the marker

Resetting the marker can replay retained EventsFeed records and create duplicates, volume spikes, storage usage, or downstream cost.

Only do this under an approved test plan:

```bash
docker compose stop cato-events-poller
mv state/marker.txt "state/marker.before-reset.$(date +%Y%m%d-%H%M%S)"
docker compose up -d cato-events-poller
```

## 12. Inspect the demonstration container controls

```bash
docker inspect cato-events-poller --format '
User={{.Config.User}}
ReadonlyRootfs={{.HostConfig.ReadonlyRootfs}}
SecurityOpt={{json .HostConfig.SecurityOpt}}
RestartPolicy={{.HostConfig.RestartPolicy.Name}}
Networks={{json .NetworkSettings.Networks}}
'
```

Expected values may include:

```text
User=10001
ReadonlyRootfs=true
SecurityOpt=["no-new-privileges:true"]
RestartPolicy=unless-stopped
```

These settings do not establish security, correctness, supportability, or production readiness.

## 13. Suggested temporary monitoring

During a supervised demonstration, watch:

- Poller container state and restarts.
- Time since the last reported successful page.
- HTTP 401, 403, 422, and 429 responses.
- DNS, TCP, and TLS errors.
- Repeated full 3,000-record pages.
- Marker presence and directory permissions.
- Cribl Source event counts.
- Route and Pipeline errors.
- Test Destination queues, storage, and backpressure.
- API-key expiration.
- Test certificate expiration.
- Unexpected access to the shared Docker network.

Monitoring suggestions do not create a support or maintenance obligation.

## 14. Troubleshooting

Use [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md) for demonstration diagnostics, including:

- Creating restricted Admin and Service API Keys.
- Authenticating directly to the Cato endpoint.
- Interpreting Cato HTTP errors.
- Discovering Cribl Docker ports and networks.
- Testing TCP and TLS.
- Sending a synthetic event.
- Validating Source, Route, Pipeline, and Destination stages.
- Repairing secret and marker permissions.
- Collecting diagnostics without intentionally exposing secrets.

## 15. End the demonstration

Stop and remove the poller:

```bash
cd /opt/catocribbler/poller
docker compose down
```

Then:

- Revoke the Cato API key.
- Remove a demonstration-only service principal.
- Remove test Cribl Source, Route, Pipeline, and Destination objects when no longer required.
- Remove the poller from external Docker networks.
- Destroy local keys, certificates, backups, and test data according to policy.
- Remove the repository clone if no longer required.
- Confirm that no production systems were altered.

## No support, maintenance, license, or warranty

No person or organization is obligated to maintain this repository, publish updates, answer questions, investigate defects, issue security notices, or assist with cleanup or incidents.

There is no license grant from the author. All material is provided “AS IS” and “AS AVAILABLE,” without warranties and without liability to the maximum extent permitted by law.

Read [`../DISCLAIMER.md`](../DISCLAIMER.md).
