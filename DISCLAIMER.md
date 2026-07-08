# Disclaimer: unsupported demonstration code

## Read this before using anything in this repository

This repository contains **experimental, non-production demonstration code** created only to illustrate one possible way to retrieve Cato Networks EventsFeed records and send them to an existing Cribl Stream environment.

It is not a supported product, integration, package, reference architecture, professional service deliverable, or production-ready implementation.

## No support

No support of any kind is provided by:

- Damon Cassell
- The repository owner or any contributor
- Cato Networks
- Cribl
- Any current or former employer of an author or contributor
- Any vendor, partner, customer, affiliate, or other person or organization

There is no support contract, service-level agreement, maintenance commitment, response-time commitment, update schedule, security-notification service, compatibility promise, or obligation to answer questions, investigate defects, merge changes, publish fixes, or maintain the repository.

Do not open a support case with Cato Networks or Cribl for this code as though it were their supported integration. Their official support organizations are not responsible for it.

## Not official, endorsed, or affiliated

This repository is independent demonstration material.

It is not:

- Authored, approved, sponsored, endorsed, certified, reviewed, or maintained by Cato Networks
- Authored, approved, sponsored, endorsed, certified, reviewed, or maintained by Cribl
- An official publication of either company
- A statement of either company's product roadmap, security posture, support policy, or recommended architecture
- Evidence of a partnership, affiliation, agency, or commercial relationship

Product names, service names, company names, and trademarks belong to their respective owners and are used only for identification.

## Non-production only

Do not use this code in a production environment.

The code has not been subjected to the engineering, quality-assurance, security, privacy, scale, reliability, compatibility, operational-readiness, legal, compliance, accessibility, documentation, or support processes normally required for production software.

It may contain defects or design limitations that can:

- Drop, duplicate, delay, reorder, corrupt, or expose events
- Lose or regress the EventsFeed marker
- Cause backlog replay or unexpected ingestion volume
- Leak API keys, certificates, account identifiers, network information, or event data
- Mis-handle authentication, authorization, TLS, retries, timeouts, or error conditions
- Overload Cato, Cribl, a downstream destination, a network, or a Docker host
- Consume unexpected storage, compute, bandwidth, licensing capacity, or paid service usage
- Stop working after changes to Cato, Cribl, Docker, Python, dependencies, operating systems, APIs, schemas, certificates, or network policies

Any person who chooses to evaluate the material is responsible for isolating it from production systems and data.

## No license granted

This repository intentionally contains **no LICENSE file** and no open-source, commercial, patent, trademark, or other license grant from the author.

Making the repository publicly viewable does not, by itself, grant permission from the author to use, copy, modify, distribute, sublicense, sell, host, deploy, or create derivative works from the material, except to the extent that a right may arise independently under applicable law or the hosting platform's terms.

Contact the applicable copyright holder before doing anything that requires permission.

## Provided “as is”

All code, configuration, examples, commands, documentation, diagrams, recommendations, and other material are provided **“AS IS”** and **“AS AVAILABLE,”** with all faults.

To the maximum extent permitted by applicable law, all warranties and conditions are disclaimed, whether express, implied, statutory, or otherwise, including warranties or conditions of:

- Merchantability
- Fitness for a particular purpose
- Title
- Non-infringement
- Accuracy
- Completeness
- Security
- Privacy
- Availability
- Reliability
- Compatibility
- Performance
- Error-free operation
- Uninterrupted operation
- Suitability for production use

No statement in this repository creates a warranty, representation, commitment, guarantee, or duty.

## Limitation of liability

To the maximum extent permitted by applicable law, Damon Cassell, the repository owner, contributors, Cato Networks, Cribl, employers, vendors, affiliates, and all other persons or organizations associated or allegedly associated with this repository will not be liable for any claim, loss, damage, cost, expense, liability, penalty, fine, outage, incident, or consequence arising from or related to the repository or its use, inability to use, evaluation, copying, modification, distribution, deployment, configuration, or operation.

This exclusion includes direct, indirect, incidental, special, exemplary, punitive, and consequential damages, including loss of data, logs, revenue, profit, business, reputation, opportunity, privacy, security, availability, or service.

## User responsibility

Anyone evaluating this repository is solely responsible for:

- Obtaining all necessary permissions and rights
- Reviewing the code and documentation independently
- Performing security, privacy, legal, compliance, and architectural review
- Protecting credentials, certificates, markers, logs, and tenant data
- Testing only with non-production systems and synthetic or approved test data
- Backing up relevant systems and state
- Monitoring for event loss, duplication, delay, and exposure
- Controlling network access, Docker privileges, and downstream destinations
- Verifying current official Cato Networks, Cribl, Docker, and dependency documentation
- Paying any costs generated by testing
- Complying with contracts, policies, laws, regulations, licenses, and third-party terms
- Removing the demonstration when testing is complete

## No assurance of updates or security fixes

The repository may be changed, abandoned, archived, deleted, or left outdated at any time without notice.

Known or unknown defects and security vulnerabilities may remain unfixed indefinitely. The absence of a reported issue does not mean the code is secure, correct, maintained, or suitable for any purpose.

## Third-party systems and terms

Use of Cato Networks, Cribl, Docker, GitHub, Python, container images, libraries, and other third-party products is governed by their own agreements, licenses, documentation, and support policies.

Nothing in this repository changes those terms or creates support rights with those providers.

## Legal review

This disclaimer is a practical statement of the author's intent and is not legal advice. Anyone relying on legal enforceability, publication rights, intellectual-property rights, or risk allocation should consult qualified legal counsel.
