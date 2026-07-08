# Security policy

## Scope

This repository deploys only the `cato-events-poller` container.

It assumes Cribl Stream already exists in Docker. Security ownership therefore spans two separately managed components:

- The new Cato poller container and its credentials/state.
- The customer's existing Cribl containers, Worker Groups, Sources, Routes, Pipelines, Destinations, certificates, and Docker networks.

Do not weaken or replace existing Cribl security controls merely to make the poller connect.

## Cato API-key type

Cato provides:

- **Admin API Keys**, tied to an individual Cato administrator.
- **Service API Keys**, tied to a service principal and intended for shared integrations and automation.

Use an Admin API Key for short-lived administrator testing when appropriate.

Use a Service API Key for a long-running production poller whenever the tenant supports that operating model. This avoids tying a production integration to a human account that can be disabled, deleted, or have its RBAC role changed unexpectedly.

## Cato API-key permissions

The poller performs read-only EventsFeed query operations.

Recommended controls:

- Use view-only permissions or **Downgrade to View**.
- Scope the associated admin or service principal to the minimum account access required.
- Restrict allowed source IPs to the Docker host's public egress IP or approved range where practical.
- Set an expiration date and rotation owner.
- Store the authoritative key in an approved secret manager.
- Revoke exposed or unused keys promptly.
- Do not pass the key on a command line.
- Do not place the key in `.env`.

The poller sends the key only in the Cato API request header:

```text
x-api-key: <api-key>
```

## API-key creation notes

Admin API Keys are created under:

```text
Resources > Admin API Keys
```

Service API Keys are created under:

```text
Resources > Service API Keys
```

A service principal is created under:

```text
Account > Administrators
```

Cato displays a newly generated key value only once. Copy it directly into the approved secret manager or protected deployment process.

## Credentials and sensitive data

Never commit:

- Cato API keys
- `.env` files
- Numeric tenant account IDs in a tenant-neutral public repository
- Private IP addresses or internal DNS names
- Cribl credentials
- Private CA certificates or private keys
- Marker files
- Production event samples
- Terminal transcripts containing secrets or tenant data
- Docker inspection output that exposes sensitive environment variables

Before every push:

```bash
git status --short
git diff --cached
```

The `.gitignore` helps, but it cannot prevent someone from explicitly forcing a secret into Git. Software remains tragically obedient.

## Local secret ownership and permissions

The poller runs as UID `10001`.

With the supplied local Compose deployment, UID `10001` must be able to read the source files used for Compose secrets and write the marker directory.

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

Do not make the API key world-readable to solve a permission problem.

## Existing Cribl Docker network security

The poller can reach Cribl through:

1. A Syslog TCP/TLS port published by the existing Cribl container, or
2. A shared external Docker network.

### Published-port model

- Bind the Cribl Syslog port only to the interfaces required by the design.
- Restrict host and network firewalls to approved poller sources.
- Use TLS for production.
- Do not publish Cribl management ports merely to support this integration.

### Shared-network model

- Attach the poller only to the specific existing Cribl network required for data delivery.
- Do not attach it to unrelated database, management, or application networks.
- Use the existing Cribl service/container DNS alias.
- Review Docker network membership periodically.

The poller requires no inbound port.

## Cribl Source security

For production:

- Use TCP rather than UDP for this integration.
- Enable TLS.
- Use a certificate whose SAN matches `CRIBL_SYSLOG_SERVER_NAME`.
- Restrict listener exposure.
- Enable persistent queues according to the customer's reliability requirements.
- Monitor Source connections and unexpected senders.

The current poller validates the Cribl server certificate but does not present a client certificate. Do not require mutual TLS unless the poller is extended to support client certificates.

## Container hardening

The supplied Compose deployment:

- Runs as UID `10001`.
- Uses a read-only root filesystem.
- Mounts `/tmp` as tmpfs.
- Applies `no-new-privileges`.
- Exposes no inbound port.
- Mounts only the API key, CA file, and marker state required for operation.

Review any Compose override that attaches the poller to an existing Cribl Docker network.

## Marker sensitivity

The marker is not an API credential, but it is tenant-specific operational state.

Protect it because:

- Losing it can replay the retained queue.
- Replacing it can cause duplicates.
- Sharing it between active pollers can create races.
- Publishing it reveals integration state.

Do not display or post the marker value.

## Event-data sensitivity

Cato events can include:

- Usernames and email addresses
- Device and hostname information
- Source and destination IP addresses
- URLs and domains
- Security detections
- Network and application metadata
- Tenant identifiers

Use synthetic examples in issues and documentation.

## Logging and diagnostics

The poller logs counts, marker length, startup state, and errors. It does not intentionally log the API key or complete marker.

Cato GraphQL error bodies can contain tenant context. Cribl Live Capture can contain complete production events. Redact diagnostics before sharing.

Use the safe collection procedure in [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md#19-collect-safe-diagnostics).

## Dependency and image maintenance

Operational owners should:

- Rebuild periodically for base-image security updates.
- Review dependency changes.
- Scan the image with the approved scanner.
- Pin approved commits or releases.
- Back up the marker before upgrades.
- Validate that an upgrade does not alter the existing Cribl containers.

## Secret exposure response

If a Cato API key is exposed:

1. Revoke it in Cato.
2. Create a replacement key with minimum read-only permissions.
3. Update `secrets/cato_api_key` with owner UID `10001` and mode `0400`.
4. Recreate only the poller container.
5. Validate Cato authentication and a successful polling cycle.
6. Review Cato API activity and security logs.
7. Remove the exposed value from Git, tickets, chat, transcripts, and other systems where possible.

If Cribl certificate private keys or credentials are exposed, follow the customer's existing Cribl and PKI incident procedures.

## Reporting a security concern

Use a private GitHub security advisory or contact the repository owner directly.

Do not put live API keys, marker values, private certificates, internal addresses, or unredacted production events in a public issue.
