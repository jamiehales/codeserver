#!/usr/bin/env bash
set -eo pipefail

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"
umask_value="${UMASK:-0022}"

if [ "$(id -u)" = '0' ]; then
  if ! getent group "$PGID" >/dev/null 2>&1; then
    groupadd -g "$PGID" coder
  else
    groupmod -g "$PGID" coder || true
  fi

  if id coder >/dev/null 2>&1; then
    usermod -u "$PUID" -g "$PGID" coder || true
  fi

  if [ -d "/home/coder" ]; then
    chown -R "$PUID":"$PGID" /home/coder || true
  fi

  export HOME=/home/coder
fi

umask "$umask_value"

if [ "$(id -u)" = '0' ]; then
  exec gosu coder "$@"
else
  exec "$@"
fi
