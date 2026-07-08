# Security policy

## Scope

This repository contains customer-managed reference code for moving Cato EventsFeed data into Cribl Stream. It is not a hosted service and does not receive credentials from users.

Security of a deployment depends on how the Docker host, Cato API key, Cribl listener, TLS certificates, and downstream destinations are managed.

## Credentials and sensitive data

Never commit any of the following:

- Cato API keys
- Cribl credentials
- `.env` files containing tenant-specific configuration
- Numeric Cato account IDs when the repository is intended to remain tenant-neutral
- Private IP addresses or internal hostnames
- Private CA certificates or client keys
- Marker files
- Production event samples
- Terminal transcripts containing credentials or tenant data

The repository `.gitignore` excludes common secret and state paths, but ignore rules are not a substitute for careful review.

Before every push, check:

```bash
git status --short
git diff --cached
```

## Cato API key recommendations

Use a dedicated service API key for this integration.

Recommended controls:

- Grant only the permissions required for EventsFeed.
- Restrict the key to the target account where supported.
- Restrict allowed source IP addresses where supported.
- Set an expiration date and documented rotation owner.
- Store the authoritative copy in an approved secret manager.
- Rotate the key immediately after suspected exposure.
- Do not pass the key as a command-line argument because process listings and shell history can expose it.

The supplied deployment reads the key from:

```text
poller/secrets/cato_api_key
```

The in-container path is:

```text
/run/secrets/cato_api_key
```

## Local file ownership and permissions

The container runs as UID `10001`. With the supplied local Docker Compose deployment, that UID must be able to read the host files used as secret sources and must be able to create and atomically replace files in `state/`.

Recommended ownership and permissions:

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

Do not make the API key world-readable merely to satisfy the container. Assign ownership to UID `10001` and retain restrictive modes.

The state directory must remain writable by UID `10001` because marker updates use atomic file replacement.

## Network security

For production:

- Use TLS between the poller and Cribl.
- Validate the Cribl certificate against a controlled CA chain.
- Set `CRIBL_SYSLOG_SERVER_NAME` to the certificate's expected DNS name.
- Restrict the Cribl listener so it accepts traffic only from approved sources.
- Restrict outbound traffic from the Docker host to the required Cato API endpoint and Cribl listener where practical.
- Do not expose the Docker daemon remotely without strong authentication and transport security.

The poller container does not require an inbound port.

## Container hardening

The supplied Compose deployment:

- Runs as non-root UID `10001`.
- Uses a read-only root filesystem.
- Mounts `/tmp` as tmpfs.
- Applies `no-new-privileges`.
- Stores the API key and CA file as Compose secrets.
- Provides write access only to the marker-state bind mount.

Review these controls before changing the Dockerfile or Compose file.

## Marker sensitivity

The marker is not an API key, but it is tenant-specific operational state. Treat it as sensitive because it can reveal integration state and because losing or replacing it can cause duplicate ingestion or backlog replay.

Do not publish marker values in issues, logs, or documentation.

## Event-data sensitivity

Cato events can contain:

- Usernames and email addresses
- Device and hostname information
- Source and destination IP addresses
- URLs and domain names
- Security detections
- Network and application metadata
- Tenant identifiers

Do not attach raw production events to public issues. Redact or generate synthetic examples.

## Logging

The poller logs counts, marker length, startup state, and errors. It does not intentionally log the API key or complete marker.

HTTP error bodies can contain useful GraphQL diagnostics and may also contain tenant context. Review them before sharing outside the authorized support group.

## Dependency and image maintenance

The image uses `python:3.12-slim` and installs Python dependencies from `poller/requirements.txt`.

Operational owners should:

- Rebuild periodically to obtain current base-image security fixes.
- Review dependency updates before deployment.
- Scan built images with the organization's approved container scanner.
- Pin approved commits or releases for production.
- Retain a rollback path and marker backup before upgrades.

## Secret exposure response

If a Cato API key is exposed:

1. Revoke or disable the exposed key in Cato.
2. Create a replacement key with minimum required permissions.
3. Replace `poller/secrets/cato_api_key` with a file owned by UID `10001` and mode `0400`.
4. Recreate the container.
5. Review Cato API activity and relevant security logs.
6. Remove the secret from Git history, tickets, chat, or logs where possible.
7. Treat the old key as compromised even if the exposure was brief.

If a private key or internal CA material is exposed, follow the organization's PKI incident process.

## Reporting a security concern

Use a private GitHub security advisory or contact the repository owner directly.

Do not include live API keys, marker values, private certificates, or unredacted production events in a public issue.
