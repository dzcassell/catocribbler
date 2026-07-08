#!/usr/bin/env bash
set -Eeuo pipefail

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

if [[ "${EUID}" -ne 0 ]]; then
  fail "Run this helper as root, for example: curl ... | sudo bash"
fi

command -v docker >/dev/null 2>&1 || fail "Docker is not installed or is not in PATH."

if docker compose version >/dev/null 2>&1; then
  echo "Docker Compose v2 is already installed:"
  docker compose version
  exit 0
fi

if [[ ! -r /etc/os-release ]]; then
  fail "This helper supports Ubuntu and Debian-family systems only."
fi

# shellcheck disable=SC1091
. /etc/os-release

case "${ID:-}:${ID_LIKE:-}" in
  ubuntu:*|debian:*|*:debian*) ;;
  *) fail "This helper supports Ubuntu and Debian-family systems only." ;;
esac

PACKAGE=""
DOCKER_SOURCE=""

if dpkg-query -W -f='${Status}\n' docker-ce 2>/dev/null | grep -q 'install ok installed'; then
  PACKAGE="docker-compose-plugin"
  DOCKER_SOURCE="Docker CE from Docker's repository"
elif dpkg-query -W -f='${Status}\n' docker.io 2>/dev/null | grep -q 'install ok installed'; then
  PACKAGE="docker-compose-v2"
  DOCKER_SOURCE="Ubuntu/Debian docker.io package"
elif snap list docker >/dev/null 2>&1; then
  fail "Docker appears to be installed as a Snap. Install Compose using the Snap's supported method or replace the Snap installation with a supported Docker package installation."
else
  fail "Could not determine whether Docker came from Docker's repository or Ubuntu's docker.io package."
fi

LEGACY_VERSION=""
if command -v docker-compose >/dev/null 2>&1; then
  LEGACY_VERSION="$(docker-compose version 2>/dev/null | head -n 1 || true)"
fi

cat <<EOF

Docker Compose v2 is missing.

Detected Docker installation:
  ${DOCKER_SOURCE}

Recommended package:
  ${PACKAGE}

Installing Compose v2 adds the 'docker compose' CLI command. It does not
convert or recreate existing containers. Existing projects can continue using
the legacy 'docker-compose' command until they are deliberately tested with v2.
EOF

if [[ -n "${LEGACY_VERSION}" ]]; then
  printf '\nLegacy Compose detected:\n  %s\n' "${LEGACY_VERSION}"
fi

printf '\nPackage-manager simulation:\n\n'
apt-get update
apt-get -s install "${PACKAGE}"

if [[ ! -r /dev/tty || ! -w /dev/tty ]]; then
  fail "An interactive terminal is required to approve installation."
fi

printf '\nInstall %s now? [Y/n]: ' "${PACKAGE}" >/dev/tty
IFS= read -r ANSWER </dev/tty
ANSWER="${ANSWER,,}"

case "${ANSWER}" in
  ""|y|yes) ;;
  n|no) fail "Installation cancelled." ;;
  *) fail "Please answer yes or no." ;;
esac

DEBIAN_FRONTEND=noninteractive apt-get install -y "${PACKAGE}"

echo
echo "Docker Compose v2 installed:"
docker compose version

echo
echo "Existing running containers:"
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'

echo
echo "Continue the Catocribbler installation with:"
echo "  curl -fsSL https://raw.githubusercontent.com/dzcassell/catocribbler/main/install.sh | sudo bash"
