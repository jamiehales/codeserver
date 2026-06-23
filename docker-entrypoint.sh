#!/bin/sh
set -eu

PUID="${PUID:-99}"
PGID="${PGID:-100}"
UMASK="${UMASK:-0002}"

# Only adjust if running as root
if [ "$(id -u)" = '0' ]; then
  # Ensure coder group exists with correct GID
  if ! getent group "$PGID" >/dev/null 2>&1; then
    groupmod -g "$PGID" coder 2>/dev/null || groupadd -g "$PGID" coder
  else
    # Try to rename conflicting group if not already named coder
    existing_group=$(getent group "$PGID" | cut -d: -f1)
    if [ "$existing_group" != "coder" ]; then
      groupmod -n coder "$existing_group" 2>/dev/null || true
    fi
  fi

  # Ensure coder user exists with correct UID
  if id coder >/dev/null 2>&1; then
    usermod -u "$PUID" -g "$PGID" coder 2>/dev/null || true
  else
    useradd -u "$PUID" -g "$PGID" -m -s /bin/bash coder
  fi

  # Fix home directory ownership
  if [ -d "/home/coder" ]; then
    chown -R "$PUID":"$PGID" /home/coder
  fi

  export HOME=/home/coder
fi

# Apply umask before starting services
umask "$UMASK"

# Call the original code-server entrypoint with all arguments
# This preserves the original startup behavior (fixuid, DOCKER_USER support, etc.)
exec /usr/bin/entrypoint.sh "$@"
