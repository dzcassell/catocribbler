#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

readonly REPOSITORY_URL="${CATOCRIBBLER_REPOSITORY_URL:-https://github.com/dzcassell/catocribbler.git}"
readonly DEFAULT_INSTALL_DIR="${CATOCRIBBLER_INSTALL_DIR:-/opt/cribbler}"
readonly INSTALL_REF="${CATOCRIBBLER_REF:-main}"
readonly DEFAULT_CATO_API_URL="${CATOCRIBBLER_CATO_API_URL:-https://api.catonetworks.com/api/v1/graphql}"
readonly DEFAULT_CRIBL_PORT="${CATOCRIBBLER_CRIBL_PORT:-9514}"
readonly DEFAULT_POLL_INTERVAL="${CATOCRIBBLER_POLL_INTERVAL:-30}"

INSTALL_DIR=""
CATO_API_URL=""
CATO_ACCOUNT_ID=""
CATO_API_KEY=""
CATO_API_KEY_CONFIRM=""
CRIBL_SYSLOG_HOST=""
CRIBL_SYSLOG_PORT=""
CRIBL_SYSLOG_TLS="false"
CRIBL_SYSLOG_SERVER_NAME=""
CRIBL_CA_SOURCE=""
POLL_INTERVAL_SECONDS=""
NETWORK_MODE=""
NETWORK_DESCRIPTION=""
CRIBL_DOCKER_NETWORK=""
PRIMARY_IPV4=""
DETECTED_CRIBL_CONTAINER=""
DETECTED_CRIBL_MAPPING=""
DETECTED_CRIBL_HOST=""
DETECTED_CRIBL_PORT=""

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

if [[ ! -r /dev/tty || ! -w /dev/tty ]]; then
  fail "An interactive terminal is required."
fi

exec 3<>/dev/tty

restore_terminal() {
  stty echo <&3 2>/dev/null || true
  unset CATO_API_KEY CATO_API_KEY_CONFIRM
}

trap restore_terminal EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

prompt() {
  local variable_name="$1"
  local message="$2"
  local default_value="${3-}"
  local response=""

  if [[ -n "${default_value}" ]]; then
    printf '%s [%s]: ' "${message}" "${default_value}" >&3
  else
    printf '%s: ' "${message}" >&3
  fi

  IFS= read -r response <&3
  response="${response:-${default_value}}"
  printf -v "${variable_name}" '%s' "${response}"
}

prompt_yes_no() {
  local variable_name="$1"
  local message="$2"
  local default_answer="$3"
  local response=""

  while true; do
    if [[ "${default_answer}" == "yes" ]]; then
      printf '%s [Y/n]: ' "${message}" >&3
    else
      printf '%s [y/N]: ' "${message}" >&3
    fi

    IFS= read -r response <&3
    response="${response,,}"

    if [[ -z "${response}" ]]; then
      printf -v "${variable_name}" '%s' "${default_answer}"
      return
    fi

    case "${response}" in
      y|yes)
        printf -v "${variable_name}" '%s' "yes"
        return
        ;;
      n|no)
        printf -v "${variable_name}" '%s' "no"
        return
        ;;
      *)
        printf 'Please answer yes or no.\n' >&3
        ;;
    esac
  done
}

prompt_secret() {
  local variable_name="$1"
  local message="$2"
  local response=""

  printf '%s: ' "${message}" >&3
  stty -echo <&3
  IFS= read -r response <&3
  stty echo <&3
  printf '\n' >&3
  printf -v "${variable_name}" '%s' "${response}"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command is missing: $1"
}

validate_install_dir() {
  [[ "${INSTALL_DIR}" == /* ]] || fail "Installation directory must be an absolute path."
  [[ "${INSTALL_DIR}" != "/" ]] || fail "Refusing to install into /."
  [[ "${INSTALL_DIR}" != "/opt" ]] || fail "Refusing to use /opt itself as the installation directory."

  if [[ -e "${INSTALL_DIR}" ]]; then
    [[ -d "${INSTALL_DIR}" ]] || fail "${INSTALL_DIR} exists and is not a directory."

    if find "${INSTALL_DIR}" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
      fail "${INSTALL_DIR} already exists and is not empty."
    fi
  fi
}

validate_port() {
  [[ "${CRIBL_SYSLOG_PORT}" =~ ^[0-9]+$ ]] || fail "Cribl port must be numeric."
  (( CRIBL_SYSLOG_PORT >= 1 && CRIBL_SYSLOG_PORT <= 65535 )) ||
    fail "Cribl port must be between 1 and 65535."
}

validate_poll_interval() {
  [[ "${POLL_INTERVAL_SECONDS}" =~ ^[0-9]+$ ]] ||
    fail "Polling interval must be a positive integer."
  (( POLL_INTERVAL_SECONDS >= 1 )) ||
    fail "Polling interval must be at least 1 second."
}

detect_primary_ipv4() {
  python3 - <<'PY'
import ipaddress
import socket

candidates = []

for target in (("1.1.1.1", 53), ("8.8.8.8", 53)):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(target)
        candidates.append(sock.getsockname()[0])
    except OSError:
        pass
    finally:
        sock.close()

try:
    for item in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
        candidates.append(item[4][0])
except OSError:
    pass

for value in candidates:
    try:
        address = ipaddress.ip_address(value)
    except ValueError:
        continue

    if not address.is_loopback and not address.is_link_local:
        print(value)
        raise SystemExit(0)
PY
}

published_bind_to_host() {
  local bind_address="$1"

  bind_address="${bind_address#[}"
  bind_address="${bind_address%]}"

  case "${bind_address}" in
    0.0.0.0|::|"")
      [[ -n "${PRIMARY_IPV4}" ]] || return 1
      printf '%s\n' "${PRIMARY_IPV4}"
      ;;
    127.*|::1)
      return 1
      ;;
    *)
      printf '%s\n' "${bind_address}"
      ;;
  esac
}

detect_published_cribl_listener() {
  local container=""
  local mapping=""
  local bind_address=""
  local host_address=""
  local host_port=""

  while IFS= read -r container; do
    [[ -n "${container}" ]] || continue

    while IFS= read -r mapping; do
      [[ -n "${mapping}" ]] || continue

      host_port="${mapping##*:}"
      bind_address="${mapping%:*}"
      host_address="$(published_bind_to_host "${bind_address}" || true)"

      if [[ -n "${host_address}" && "${host_port}" =~ ^[0-9]+$ ]]; then
        DETECTED_CRIBL_CONTAINER="${container}"
        DETECTED_CRIBL_MAPPING="${mapping}"
        DETECTED_CRIBL_HOST="${host_address}"
        DETECTED_CRIBL_PORT="${host_port}"
        return 0
      fi
    done < <(docker port "${container}" "${DEFAULT_CRIBL_PORT}/tcp" 2>/dev/null || true)
  done < <(docker ps --filter 'name=cribl' --format '{{.Names}}')

  return 1
}

configure_manual_published_listener() {
  NETWORK_MODE="1"
  NETWORK_DESCRIPTION="Published host TCP port"

  if [[ -n "${PRIMARY_IPV4}" ]]; then
    prompt CRIBL_SYSLOG_HOST \
      "Address of the Docker host running Cribl" \
      "${PRIMARY_IPV4}"
  else
    while [[ -z "${CRIBL_SYSLOG_HOST}" ]]; do
      prompt CRIBL_SYSLOG_HOST \
        "IP address or DNS name of the Docker host running Cribl"
    done
  fi

  [[ ! "${CRIBL_SYSLOG_HOST}" =~ [[:space:]] ]] ||
    fail "Cribl host cannot contain whitespace."

  case "${CRIBL_SYSLOG_HOST}" in
    localhost|127.*|::1)
      fail "Do not use localhost or a loopback address for Cribl."
      ;;
  esac

  prompt CRIBL_SYSLOG_PORT "Published Cribl Syslog TCP port" "${DEFAULT_CRIBL_PORT}"
  validate_port
}

configure_shared_network() {
  NETWORK_MODE="2"
  NETWORK_DESCRIPTION="Shared external Docker network"

  printf '\nAvailable Docker networks:\n' >&3
  docker network ls --format '  {{.Name}}' >&3
  printf '\n' >&3

  while [[ -z "${CRIBL_DOCKER_NETWORK}" ]]; do
    prompt CRIBL_DOCKER_NETWORK \
      "Docker network used by the non-production Cribl Worker"
  done

  [[ ! "${CRIBL_DOCKER_NETWORK}" =~ [[:space:]] ]] ||
    fail "Docker network name cannot contain whitespace."

  docker network inspect "${CRIBL_DOCKER_NETWORK}" >/dev/null 2>&1 ||
    fail "Docker network does not exist: ${CRIBL_DOCKER_NETWORK}"

  while [[ -z "${CRIBL_SYSLOG_HOST}" ]]; do
    prompt CRIBL_SYSLOG_HOST \
      "Cribl Worker container, service, or network-alias name"
  done

  [[ ! "${CRIBL_SYSLOG_HOST}" =~ [[:space:]] ]] ||
    fail "Cribl host cannot contain whitespace."

  prompt CRIBL_SYSLOG_PORT "Cribl Syslog TCP port inside the Docker network" "${DEFAULT_CRIBL_PORT}"
  validate_port
}

if [[ "${EUID}" -ne 0 ]]; then
  fail "Run this installer as root, for example: curl ... | sudo bash"
fi

for command_name in git docker python3; do
  require_command "${command_name}"
done

docker info >/dev/null 2>&1 || fail "Docker is not running or is not accessible."
docker compose version >/dev/null 2>&1 || fail "Docker Compose v2 is required."

PRIMARY_IPV4="$(detect_primary_ipv4 || true)"

cat >&3 <<'NOTICE'

Cato EventsFeed to Cribl demonstration installer

UNSUPPORTED, NON-PRODUCTION DEMONSTRATION CODE.
No support, warranty, maintenance commitment, production-readiness assurance,
or license grant is provided by the repository owner, Cato Networks, Cribl,
contributors, employers, vendors, partners, or anyone else.

This installer will:
  * clone the repository into a directory you select;
  * create local configuration, secret, and marker directories;
  * build the poller image;
  * test Cato API authentication;
  * test the connection to an existing Cribl Syslog Source;
  * optionally send one synthetic event;
  * start continuous polling only after an explicit final confirmation.

An empty EventsFeed marker can replay retained events in pages of up to 3,000.
Use only an isolated, approved, non-production environment.

NOTICE

prompt ACCEPTANCE "Type I UNDERSTAND to continue"
[[ "${ACCEPTANCE}" == "I UNDERSTAND" ]] || fail "Disclaimer was not accepted."

while true; do
  prompt INSTALL_DIR "Installation directory" "${DEFAULT_INSTALL_DIR}"

  if [[ "${INSTALL_DIR}" != /* ]]; then
    printf 'Please enter an absolute path, such as /opt/cribbler.\n' >&3
    continue
  fi

  if [[ "${INSTALL_DIR}" == "/" || "${INSTALL_DIR}" == "/opt" ]]; then
    printf 'Choose a dedicated directory, not %s.\n' "${INSTALL_DIR}" >&3
    continue
  fi

  if [[ -e "${INSTALL_DIR}" ]] &&
     find "${INSTALL_DIR}" -mindepth 1 -maxdepth 1 -print -quit | grep -q .
  then
    printf '%s already exists and is not empty.\n' "${INSTALL_DIR}" >&3
    continue
  fi

  break
done

validate_install_dir

prompt CATO_API_URL "Cato GraphQL API URL" "${DEFAULT_CATO_API_URL}"
[[ "${CATO_API_URL}" == https://* ]] || fail "Cato API URL must begin with https://"
[[ ! "${CATO_API_URL}" =~ [[:space:]] ]] || fail "Cato API URL cannot contain whitespace."

while true; do
  prompt CATO_ACCOUNT_ID "Numeric Cato account ID"
  [[ "${CATO_ACCOUNT_ID}" =~ ^[0-9]+$ ]] && break
  printf 'The Cato account ID must contain digits only.\n' >&3
done

if detect_published_cribl_listener; then
  cat >&3 <<DETECTED

The installer found a running Cribl container with a published Syslog listener:

  Cribl container:            ${DETECTED_CRIBL_CONTAINER}
  Docker port mapping:        ${DETECTED_CRIBL_MAPPING}
  Address the poller will use: ${DETECTED_CRIBL_HOST}:${DETECTED_CRIBL_PORT}

For most installations, accept this detected setting. No address needs to be
looked up or typed manually.

DETECTED

  prompt_yes_no USE_DETECTED_CRIBL "Use this detected Cribl listener" "yes"

  if [[ "${USE_DETECTED_CRIBL}" == "yes" ]]; then
    NETWORK_MODE="1"
    NETWORK_DESCRIPTION="Auto-detected published host TCP port"
    CRIBL_SYSLOG_HOST="${DETECTED_CRIBL_HOST}"
    CRIBL_SYSLOG_PORT="${DETECTED_CRIBL_PORT}"
  else
    cat >&3 <<'ALTERNATIVES'

Choose an alternative only when the detected listener is not the intended one:

  1. Enter a different published Cribl host address and TCP port
  2. Join the Cribl Docker network directly (advanced)

ALTERNATIVES

    while true; do
      prompt NETWORK_MODE "Alternative connection method: choose 1 or 2" "1"
      case "${NETWORK_MODE}" in
        1)
          configure_manual_published_listener
          break
          ;;
        2)
          configure_shared_network
          break
          ;;
        *)
          printf 'Enter 1 or 2.\n' >&3
          ;;
      esac
    done
  fi
else
  cat >&3 <<NO_DETECTION

The installer did not find a running Cribl container publishing TCP port
${DEFAULT_CRIBL_PORT}. This can happen when Cribl uses another port, runs on
another host, or is reachable only through a Docker network.

Choose how to reach it:

  1. Published host TCP port
     Use the Docker host address detected by this installer and enter the
     published Syslog port. Detected host address: ${PRIMARY_IPV4:-not detected}

  2. Shared external Docker network (advanced)
     Use an existing Cribl Docker network and the Cribl Worker container name.

NO_DETECTION

  while true; do
    prompt NETWORK_MODE "Connection method: choose 1 or 2" "1"
    case "${NETWORK_MODE}" in
      1)
        configure_manual_published_listener
        break
        ;;
      2)
        configure_shared_network
        break
        ;;
      *)
        printf 'Enter 1 or 2.\n' >&3
        ;;
    esac
  done
fi

prompt_yes_no USE_TLS "Use TLS for the Cribl Syslog connection" "no"

if [[ "${USE_TLS}" == "yes" ]]; then
  CRIBL_SYSLOG_TLS="true"

  prompt CRIBL_SYSLOG_SERVER_NAME \
    "TLS server name from the Cribl certificate" \
    "${CRIBL_SYSLOG_HOST}"

  [[ ! "${CRIBL_SYSLOG_SERVER_NAME}" =~ [[:space:]] ]] ||
    fail "TLS server name cannot contain whitespace."

  while true; do
    prompt CRIBL_CA_SOURCE "Path to the PEM CA chain that validates Cribl"
    [[ -f "${CRIBL_CA_SOURCE}" ]] && break
    printf 'File not found: %s\n' "${CRIBL_CA_SOURCE}" >&3
  done
else
  CRIBL_SYSLOG_TLS="false"
  CRIBL_SYSLOG_SERVER_NAME="${CRIBL_SYSLOG_HOST}"
fi

prompt POLL_INTERVAL_SECONDS \
  "Polling interval in seconds" \
  "${DEFAULT_POLL_INTERVAL}"

validate_poll_interval

while true; do
  prompt_secret CATO_API_KEY "Paste the new Cato API key"

  if [[ -z "${CATO_API_KEY}" ]]; then
    printf 'The API key cannot be empty.\n' >&3
    continue
  fi

  prompt_secret CATO_API_KEY_CONFIRM "Paste the new Cato API key again"

  if [[ "${CATO_API_KEY}" == "${CATO_API_KEY_CONFIRM}" ]]; then
    break
  fi

  printf 'The API-key entries did not match. Try again.\n' >&3
done

cat >&3 <<SUMMARY

Installation summary
  Repository:         ${REPOSITORY_URL}
  Git ref:            ${INSTALL_REF}
  Install path:       ${INSTALL_DIR}
  Cato API URL:       ${CATO_API_URL}
  Cato account ID:    ${CATO_ACCOUNT_ID}
  Connection method:  ${NETWORK_DESCRIPTION}
  Cribl host:         ${CRIBL_SYSLOG_HOST}
  Cribl port:         ${CRIBL_SYSLOG_PORT}
  Cribl TLS:          ${CRIBL_SYSLOG_TLS}
  Poll interval:      ${POLL_INTERVAL_SECONDS}

The API key is intentionally not displayed.
SUMMARY

prompt_yes_no CONTINUE_INSTALL "Create this installation" "yes"
[[ "${CONTINUE_INSTALL}" == "yes" ]] || fail "Installation cancelled."

mkdir -p "$(dirname "${INSTALL_DIR}")"
git clone "${REPOSITORY_URL}" "${INSTALL_DIR}"
git -C "${INSTALL_DIR}" checkout --detach "${INSTALL_REF}"

readonly POLLER_DIR="${INSTALL_DIR}/poller"

[[ -f "${POLLER_DIR}/compose.yaml" ]] ||
  fail "The selected repository ref does not contain poller/compose.yaml."
[[ -f "${POLLER_DIR}/.dockerignore" ]] ||
  fail "The selected repository ref does not contain poller/.dockerignore."

grep -Fxq 'secrets/' "${POLLER_DIR}/.dockerignore" ||
  fail ".dockerignore does not exclude secrets/."
grep -Fxq 'state/' "${POLLER_DIR}/.dockerignore" ||
  fail ".dockerignore does not exclude state/."
grep -Fxq '.env' "${POLLER_DIR}/.dockerignore" ||
  fail ".dockerignore does not exclude .env."

cd "${POLLER_DIR}"
mkdir -p secrets state

cat > .env <<EOF
CATO_API_URL=${CATO_API_URL}
CATO_ACCOUNT_ID=${CATO_ACCOUNT_ID}
CATO_API_KEY_FILE=/run/secrets/cato_api_key

CRIBL_SYSLOG_HOST=${CRIBL_SYSLOG_HOST}
CRIBL_SYSLOG_PORT=${CRIBL_SYSLOG_PORT}
CRIBL_SYSLOG_TLS=${CRIBL_SYSLOG_TLS}
CRIBL_SYSLOG_SERVER_NAME=${CRIBL_SYSLOG_SERVER_NAME}
CRIBL_SYSLOG_CA_FILE=/run/secrets/cribl_ca.pem

POLL_INTERVAL_SECONDS=${POLL_INTERVAL_SECONDS}
STATE_FILE=/state/marker.txt
LOG_LEVEL=INFO
SYSLOG_HOSTNAME=cato-events-poller
EOF

printf '%s' "${CATO_API_KEY}" > secrets/cato_api_key
unset CATO_API_KEY CATO_API_KEY_CONFIRM

if [[ "${CRIBL_SYSLOG_TLS}" == "true" ]]; then
  install -m 0400 "${CRIBL_CA_SOURCE}" secrets/cribl_ca.pem
else
  : > secrets/cribl_ca.pem
fi

if [[ "${NETWORK_MODE}" == "2" ]]; then
  cat > compose.override.yaml <<EOF
services:
  cato-events-poller:
    networks:
      - cribl_existing

networks:
  cribl_existing:
    external: true
    name: "${CRIBL_DOCKER_NETWORK}"
EOF
fi

chmod 0600 .env
chown 10001:10001 \
  secrets \
  secrets/cato_api_key \
  secrets/cribl_ca.pem \
  state
chmod 0700 secrets state
chmod 0400 secrets/cato_api_key secrets/cribl_ca.pem

docker compose config >/dev/null

printf '\nBuilding the demonstration image...\n' >&3
docker compose build --pull --no-cache

printf '\nRunning Cato API preflight...\n' >&3
docker compose run \
  --rm \
  --no-deps \
  --entrypoint python \
  cato-events-poller \
  -c '
import poller

marker = poller.read_marker()
result = poller.fetch(marker)
events = poller.extract_events(result)
fetched = int(result.get("fetchedCount") or 0)
returned_marker = result.get("marker") or ""

if fetched != len(events):
    raise SystemExit(
        f"Fetched/decoded mismatch: fetched={fetched}, decoded={len(events)}"
    )

print(
    "CATO API PREFLIGHT PASS "
    f"fetched={fetched} "
    f"decoded={len(events)} "
    f"current_marker_len={len(marker)} "
    f"returned_marker_len={len(returned_marker)}"
)
'

printf '\nRunning Cribl TCP/TLS preflight...\n' >&3
docker compose run \
  --rm \
  --no-deps \
  --entrypoint python \
  cato-events-poller \
  -c '
import poller

with poller.open_syslog_socket() as connection:
    peer = connection.getpeername()

print(
    "CRIBL CONNECTION PREFLIGHT PASS "
    f"host={poller.SYSLOG_HOST} "
    f"port={poller.SYSLOG_PORT} "
    f"tls={poller.SYSLOG_TLS} "
    f"peer={peer}"
)
'

prompt_yes_no SEND_SYNTHETIC "Send one synthetic test event to Cribl" "yes"

if [[ "${SEND_SYNTHETIC}" == "yes" ]]; then
  docker compose run \
    --rm \
    --no-deps \
    --entrypoint python \
    cato-events-poller \
    -c '
import time
import poller

event = {
    "time": int(time.time() * 1000),
    "event_type": "Catocribbler Installer Synthetic Test",
    "vendor": "cato",
    "product": "cato_sase",
    "installer_test": True,
}

with poller.open_syslog_socket() as connection:
    connection.sendall(poller.syslog_line(event))

print("SYNTHETIC CRIBL EVENT SENT")
'
fi

readonly INSTALLED_COMMIT="$(git -C "${INSTALL_DIR}" rev-parse HEAD)"
readonly INSTALL_TIME="$(date --iso-8601=seconds)"

cat > "${INSTALL_DIR}/INSTALLATION_INFO.txt" <<EOF
Installation time: ${INSTALL_TIME}
Repository: ${REPOSITORY_URL}
Requested ref: ${INSTALL_REF}
Installed commit: ${INSTALLED_COMMIT}
Install directory: ${INSTALL_DIR}
Cato API URL: ${CATO_API_URL}
Cato account ID: ${CATO_ACCOUNT_ID}
Connection method: ${NETWORK_DESCRIPTION}
Cribl host: ${CRIBL_SYSLOG_HOST}
Cribl port: ${CRIBL_SYSLOG_PORT}
Cribl TLS: ${CRIBL_SYSLOG_TLS}
EOF

chmod 0600 "${INSTALL_DIR}/INSTALLATION_INFO.txt"

cat >&3 <<'START_WARNING'

Preflights passed.

Continuous polling is still stopped.

Starting with an empty marker can replay all retained EventsFeed records, possibly
in consecutive 3,000-record pages. Confirm the non-production Cribl Destination
has enough capacity and that replay is approved.

START_WARNING

prompt START_CONFIRMATION \
  "Type START to begin continuous polling, or press Enter to leave it stopped"

if [[ "${START_CONFIRMATION}" == "START" ]]; then
  docker compose up -d
  printf '\nPoller started.\n' >&3
  docker compose ps
  docker compose logs --tail=20 cato-events-poller || true
else
  printf '\nPoller was installed and tested but not started.\n' >&3
fi

cat >&3 <<COMPLETE

Installation complete.

Install directory:
  ${INSTALL_DIR}

Installed commit:
  ${INSTALLED_COMMIT}

Useful commands:
  cd ${POLLER_DIR}
  docker compose ps
  docker compose logs -f cato-events-poller
  docker compose up -d
  docker compose down

The API key is stored only in:
  ${POLLER_DIR}/secrets/cato_api_key

COMPLETE
