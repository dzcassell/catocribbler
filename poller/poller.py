#!/usr/bin/env python3
"""Poll Cato EventsFeed and forward normalized records to Cribl over RFC 5424 syslog."""

from __future__ import annotations

import json
import logging
import os
import re
import socket
import ssl
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

APPNAME = "cato-events"
HOSTNAME = os.environ.get("SYSLOG_HOSTNAME", "cato-events-poller")
MAX_FETCH = 3000

QUERY = """
query eventsFeed($accountIDs: [ID!]!, $marker: String) {
  eventsFeed(accountIDs: $accountIDs, marker: $marker) {
    marker
    fetchedCount
    accounts {
      id
      records {
        time
        eventType
        eventSubType
        fieldsMap
      }
    }
  }
}
"""


def required_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"Required environment variable is missing: {name}")
    return value


API_URL = required_env("CATO_API_URL")
ACCOUNT_ID = required_env("CATO_ACCOUNT_ID")
API_KEY_FILE = Path(required_env("CATO_API_KEY_FILE"))
SYSLOG_HOST = required_env("CRIBL_SYSLOG_HOST")
SYSLOG_PORT = int(os.environ.get("CRIBL_SYSLOG_PORT", "9514"))
SYSLOG_TLS = os.environ.get("CRIBL_SYSLOG_TLS", "true").lower() == "true"
SYSLOG_SERVER_NAME = os.environ.get("CRIBL_SYSLOG_SERVER_NAME", SYSLOG_HOST)
SYSLOG_CA_FILE = os.environ.get("CRIBL_SYSLOG_CA_FILE")
POLL_INTERVAL = int(os.environ.get("POLL_INTERVAL_SECONDS", "30"))
STATE_FILE = Path(os.environ.get("STATE_FILE", "/state/marker.txt"))
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO").upper()

logging.basicConfig(
    level=getattr(logging, LOG_LEVEL, logging.INFO),
    format="%(asctime)s %(levelname)s %(message)s",
)
LOG = logging.getLogger("cato-events-poller")


def read_api_key() -> str:
    value = API_KEY_FILE.read_text(encoding="utf-8").strip()
    if not value:
        raise RuntimeError("Cato API key file is empty")
    return value


def build_session() -> requests.Session:
    retry = Retry(
        total=5,
        connect=5,
        read=5,
        status=5,
        backoff_factor=1.0,
        status_forcelist=(429, 500, 502, 503, 504),
        allowed_methods=frozenset({"POST"}),
        respect_retry_after_header=True,
    )
    client = requests.Session()
    client.mount("https://", HTTPAdapter(max_retries=retry))
    return client


HTTP = build_session()


def read_marker() -> str:
    try:
        return STATE_FILE.read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        return ""


def write_marker(marker: str) -> None:
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=STATE_FILE.parent, prefix="marker.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(marker)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, STATE_FILE)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def snake_case(value: str) -> str:
    value = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", value)
    value = re.sub(r"[^A-Za-z0-9]+", "_", value)
    return value.strip("_").lower() or "field"


def normalize(account_id: Any, record: dict[str, Any]) -> dict[str, Any]:
    event: dict[str, Any] = {
        "time": record.get("time"),
        "event_type": record.get("eventType"),
        "event_sub_type": record.get("eventSubType"),
        "account_id": str(account_id),
        "vendor": "cato",
        "product": "cato_sase",
    }

    fields = record.get("fieldsMap") or {}
    if isinstance(fields, dict):
        for key, value in fields.items():
            event.setdefault(snake_case(str(key)), value)
    else:
        event["fields_map"] = fields

    return {key: value for key, value in event.items() if value is not None}


def fetch(marker: str) -> dict[str, Any]:
    response = HTTP.post(
        API_URL,
        headers={
            "Content-Type": "application/json",
            "x-api-key": read_api_key(),
        },
        json={
            "query": QUERY,
            "variables": {
                "accountIDs": [ACCOUNT_ID],
                "marker": marker or None,
            },
        },
        timeout=(10, 60),
    )
    response.raise_for_status()
    payload = response.json()
    if payload.get("errors"):
        raise RuntimeError(json.dumps(payload["errors"], separators=(",", ":")))
    return payload["data"]["eventsFeed"]


def open_syslog_socket() -> socket.socket:
    raw = socket.create_connection((SYSLOG_HOST, SYSLOG_PORT), timeout=15)
    if not SYSLOG_TLS:
        return raw

    context = ssl.create_default_context(cafile=SYSLOG_CA_FILE or None)
    return context.wrap_socket(raw, server_hostname=SYSLOG_SERVER_NAME)


def syslog_line(event: dict[str, Any]) -> bytes:
    timestamp = datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace(
        "+00:00", "Z"
    )
    payload = json.dumps(event, separators=(",", ":"), ensure_ascii=False)
    return f"<134>1 {timestamp} {HOSTNAME} {APPNAME} - - - {payload}\n".encode(
        "utf-8"
    )


def send_page(events: list[dict[str, Any]]) -> None:
    if not events:
        return
    with open_syslog_socket() as sock:
        for event in events:
            sock.sendall(syslog_line(event))


def extract_events(result: dict[str, Any]) -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    for account in result.get("accounts") or []:
        account_id = account.get("id")
        for record in account.get("records") or []:
            events.append(normalize(account_id, record))
    return events


def main() -> None:
    marker = read_marker()
    LOG.info("starting marker_len=%d", len(marker))

    while True:
        try:
            result = fetch(marker)
            events = extract_events(result)
            send_page(events)

            next_marker = result.get("marker") or marker
            if next_marker != marker:
                write_marker(next_marker)
                marker = next_marker

            fetched = int(result.get("fetchedCount") or 0)
            LOG.info(
                "fetched=%d sent=%d marker_len=%d",
                fetched,
                len(events),
                len(marker),
            )

            if fetched < MAX_FETCH:
                time.sleep(POLL_INTERVAL)
        except Exception:
            LOG.exception("poll failed")
            time.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    main()
