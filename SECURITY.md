# Security notice

> [!CAUTION]
> This repository contains unsupported, non-production demonstration code. It is not a supported product, secure reference architecture, certified integration, or production implementation.

No security support, maintenance, review, certification, warranty, or incident-response service is provided by Damon Cassell, the repository owner, Cato Networks, Cribl, any employer, contributor, vendor, partner, or anyone else.

There is no license grant from the author. Read [`DISCLAIMER.md`](DISCLAIMER.md).

## Do not use in production

Do not use this material with production systems, credentials, event data, networks, Worker Groups, Destinations, or business processes.

Use only an isolated, disposable test environment with synthetic or specifically approved test data and a short-lived, minimally scoped test credential.

## Evaluator responsibility

Anyone evaluating the repository is solely responsible for independent security, privacy, legal, compliance, architectural, and operational review.

The demonstration can expose information, lose or duplicate events, replay retained data, consume resources, connect to unintended systems, or stop working without notice.

## Sensitive material

Do not commit, publish, or share credentials, environment files, account identifiers, private addresses, certificates, marker values, event payloads, or diagnostic output containing tenant information.

Revoke demonstration credentials and remove test data, Docker-network access, and Cribl test objects when evaluation ends.

## No vulnerability-management commitment

There is no commitment to monitor dependencies, publish advisories, investigate reports, issue fixes, rebuild images, maintain compatibility, or notify anyone of defects or vulnerabilities.

The absence of a reported issue is not evidence that the code is secure.

## Additional cautions

See:

- [`DISCLAIMER.md`](DISCLAIMER.md) for the full no-support, no-license, no-warranty, and limitation-of-liability notice.
- [`docs/INSTALL.md`](docs/INSTALL.md) for isolated demonstration setup.
- [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) for limited self-service diagnostics.

All material is provided “AS IS” and “AS AVAILABLE,” with all faults, no warranties or conditions, and no liability to the maximum extent permitted by applicable law.
