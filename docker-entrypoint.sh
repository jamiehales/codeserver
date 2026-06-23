#!/bin/sh
set -eu

PUID="${PUID:-99}"
PGID="${PGID:-100}"
UMASK="${UMASK:-0002}"

# Only adjust if running as root
if [ "$(id -u)" = '0' ]; then
  # Adjust coder user and group IDs to match PUID/PGID
  if getent group "$PGID" >/dev/null 2>&1; then
    # Group exists with PGID, rename it to coder if needed
    existing_group=$(getent group "$PGID" | cut -d: -f1)
    if [ "$existing_group" != "coder" ]; then
      groupmod -n coder "$existing_group" 2>/dev/null || true
    fi
  else
    # Group doesn't exist, create or modify to PGID
    groupmod -g "$PGID" coder 2>/dev/null || groupadd -g "$PGID" coder
  fi

  # Adjust user ID
  usermod -u "$PUID" -g "$PGID" coder 2>/dev/null || true

  # Fix home directory ownership
  if [ -d "/home/coder" ]; then
    chown -R "$PUID":"$PGID" /home/coder
  fi

  export HOME=/home/coder
fi

# Apply umask before starting services
umask "$UMASK"

# Call the original code-server entrypoint with all args
exec /usr/bin/entrypoint.sh "$@"
