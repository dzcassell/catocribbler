# Demonstration lifecycle, backup, cleanup, and monitoring

> [!CAUTION]
> **UNSUPPORTED, NON-PRODUCTION DEMONSTRATION ONLY.** This repository is not supported by Damon Cassell, Cato Networks, Cribl, any employer, contributor, vendor, partner, or anyone else. There is no license grant, no warranty, no maintenance promise, and no obligation to assist. Do not operate this code as a production service. Read [`../DISCLAIMER.md`](../DISCLAIMER.md).

This guide assumes the interactive installer was used. The default installation directory is `/opt/cribbler`, but the evaluator may select another absolute path.

Set the actual installation directory before using any command:

```bash
INSTALL_DIR=${INSTALL_DIR:-/opt/cribbler}
POLLER_DIR="${INSTALL_DIR}/poller"
cd "${POLLER_DIR}"
```

## 1. Status and logs

```bash
docker compose ps
docker compose logs --tail=100 cato-events-poller
```

Follow logs:

```bash
docker compose logs -f cato-events-poller
```

A successful cycle resembles:

```text
INFO Fetched=144 Sent=144 marker_len=180
```

`Fetched=N Sent=N` means the poller wrote the records to the Cribl socket. It does not prove Cribl parsed, routed, transformed, persisted, or delivered them correctly.

## 2. Start, stop, restart, and remove

Start:

```bash
docker compose up -d
```

Stop without removing the container:

```bash
docker compose stop cato-events-poller
```

Restart:

```bash
docker compose restart cato-events-poller
```

Recreate after configuration or key changes:

```bash
docker compose up -d --force-recreate cato-events-poller
```

Remove only the poller container and its private Compose network while preserving local configuration, secrets, and marker state:

```bash
docker compose down
```

Run these commands only from the poller directory. They must not target the existing Cribl Compose project.

## 3. Marker state

The marker is stored in:

```text
<install-directory>/poller/state/marker.txt
```

Inspect metadata without displaying the marker:

```bash
ls -l state/marker.txt
wc -c state/marker.txt
sha256sum state/marker.txt
```

Do not:

- Edit the marker.
- Publish its value.
- Share one state directory between active pollers.
- Restore an older marker unless replay is intentional and approved.
- Assume the marker has a fixed length.

Losing or resetting it can replay retained events and create duplicates, volume spikes, storage use, or downstream cost.

## 4. Installation metadata

The interactive installer records non-secret details in:

```text
<install-directory>/INSTALLATION_INFO.txt
```

Review:

```bash
cat "${INSTALL_DIR}/INSTALLATION_INFO.txt"
git -C "${INSTALL_DIR}" rev-parse HEAD
git -C "${INSTALL_DIR}" status --short
```

Local `.env`, secrets, state, installation metadata, and Compose overrides are ignored by Git.

## 5. Protected demonstration backup

Back up only when the approved test plan requires continuity:

```bash
umask 077
BACKUP="/root/cribbler-demo-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "${BACKUP}"

cp -a .env "${BACKUP}/"
cp -a secrets "${BACKUP}/"
cp -a state "${BACKUP}/"
test -e compose.override.yaml && cp -a compose.override.yaml "${BACKUP}/"
cp -a "${INSTALL_DIR}/INSTALLATION_INFO.txt" "${BACKUP}/" 2>/dev/null || true
git -C "${INSTALL_DIR}" rev-parse HEAD > "${BACKUP}/git-commit.txt"

chmod -R go-rwx "${BACKUP}"
printf 'Backup created: %s\n' "${BACKUP}"
```

The backup can contain credentials, certificates, tenant identifiers, and marker state. Protect and destroy it according to policy.

## 6. Rotate the Cato API key

Create a new restricted Service API Key in CMA before changing the local file. Revoke an exposed key immediately; otherwise validate the replacement before revoking the old key.

```bash
umask 077
read -rsp 'New Cato API key: ' CATO_KEY
printf '%s' "${CATO_KEY}" > secrets/cato_api_key.new
unset CATO_KEY
printf '\n'

chown 10001:10001 secrets/cato_api_key.new
chmod 0400 secrets/cato_api_key.new
mv secrets/cato_api_key.new secrets/cato_api_key
```

Run the Cato preflight from [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md), then recreate the container:

```bash
docker compose up -d --force-recreate cato-events-poller
docker compose logs --tail=100 cato-events-poller
```

Revoke the old key after validation.

## 7. Change the account or endpoint

Changing the account or regional endpoint changes the EventsFeed context. Do not reuse the previous account's marker.

```bash
docker compose stop cato-events-poller

if test -e state/marker.txt; then
  mv state/marker.txt \
    "state/marker.previous-account.$(date +%Y%m%d-%H%M%S)"
fi

nano .env
```

Run the Cato preflight before restarting. A new account can create a large retained-events replay.

## 8. Change Cribl connectivity

Edit `.env` and, when using a shared external Docker network, `compose.override.yaml`.

Validate the resolved Compose configuration:

```bash
docker compose config >/dev/null
```

Then run:

1. Cribl TCP or TLS preflight.
2. Synthetic event test.
3. Cribl Source, Route, Pipeline, and Destination validation.
4. Container recreation.

```bash
docker compose up -d --force-recreate cato-events-poller
```

## 9. Evaluate a newer commit

There is no supported upgrade path or compatibility promise.

Review changes before updating:

```bash
cd "${INSTALL_DIR}"
CURRENT_COMMIT="$(git rev-parse HEAD)"
printf 'Current commit: %s\n' "${CURRENT_COMMIT}"

git fetch origin
git log --oneline --decorate HEAD..origin/main
git diff --stat HEAD..origin/main
```

Back up marker state if continuity matters. Check out only a reviewed commit:

```bash
git checkout --detach <reviewed-commit-sha>
cd poller

docker compose config >/dev/null
docker compose build --pull --no-cache
```

Re-run Cato authentication, Cribl connectivity, and synthetic-event validation before recreating the continuous poller.

## 10. Inspect container controls

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

These controls do not prove security or production readiness.

## 11. Temporary monitoring

During a supervised demonstration, watch:

- Container state and restarts.
- Time since the last successful page.
- HTTP 401, 403, 422, and 429 responses.
- DNS, TCP, and TLS errors.
- Repeated full 3,000-record pages.
- Marker creation and permissions.
- Cribl Source counts.
- Route and Pipeline errors.
- Destination queues, storage, and backpressure.
- API-key and certificate expiration.

## 12. End the demonstration

```bash
cd "${POLLER_DIR}"
docker compose down
```

Then:

1. Revoke the Cato Service API Key.
2. Remove the demonstration-only service principal when no longer needed.
3. Remove test-only Cribl objects when appropriate.
4. Remove the poller from external Docker networks.
5. Destroy local keys, CA files, marker state, backups, and test data according to policy.
6. Remove the installation directory:

   ```bash
   rm -rf -- "${INSTALL_DIR}"
   ```

## No support, maintenance, license, or warranty

No person or organization is obligated to maintain this repository, answer questions, investigate defects, issue security notices, or assist with incidents. All material is provided “AS IS” and “AS AVAILABLE.” Read [`../DISCLAIMER.md`](../DISCLAIMER.md).
