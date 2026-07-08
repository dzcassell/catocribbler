# catocribbler

Customer-ready guidance and reference assets for integrating **Cato Networks EventsFeed** logs with **Cribl Stream**.

![Cato EventsFeed to Cribl Stream architecture](assets/cato_cribl_architecture.png)

## Contents

- [`docs/Cato_EventsFeed_to_Cribl_Stream_Customer_How-To.pdf`](docs/Cato_EventsFeed_to_Cribl_Stream_Customer_How-To.pdf) — print-ready customer implementation guide
- [`docs/Cato_EventsFeed_to_Cribl_Stream_Customer_How-To.docx`](docs/Cato_EventsFeed_to_Cribl_Stream_Customer_How-To.docx) — editable source document
- [`assets/cato_cribl_architecture.png`](assets/cato_cribl_architecture.png) — reference architecture diagram

## Scope

The guide covers:

- Cato tenant preparation and service-key handling
- EventsFeed polling and marker persistence
- Syslog delivery to Cribl Stream
- Cribl Source, Pipeline, Route, and filesystem-destination configuration
- JSON normalization into top-level Cribl fields
- Validation, troubleshooting, and production hardening

## Security

This repository intentionally contains no API keys, tenant account identifiers, private IP addresses, passwords, or customer-specific hostnames. Use placeholders and secret-management controls when adapting the examples.

Do not commit Cato API keys or other credentials. Store secrets in a vault, orchestrator secret, or protected local file with restrictive permissions.

## Product documentation

Validate implementation details against the current official Cato Networks and Cribl documentation before production deployment, since APIs and product interfaces evolve because apparently software dislikes remaining still.

## Disclaimer

This is an independent implementation guide and is not an official Cato Networks or Cribl publication. Product names and trademarks belong to their respective owners.
