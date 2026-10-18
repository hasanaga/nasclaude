#!/usr/bin/env bash
# Container entrypoint. Runs as the unprivileged agent user (never root).
set -euo pipefail

log() { printf '[entrypoint] %s\n' "$*"; }

if [[ "$(id -u)" == "0" ]]; then
  log "Refusing to run as root. Set user: \"\${PUID}:\${PGID}\" in compose."
  exit 1
fi

# Real write test: [[ -w ]] is unreliable with NAS ACLs (UGREEN UGOS reported /data
# as writable while every write failed), so create and remove a probe file instead.
require_writable() {
  local dir="$1" what="$2" probe="$1/.nas-agent-write-test.$$"
  if ( : > "$probe" ) 2>/dev/null && rm -f "$probe" 2>/dev/null; then
    return 0
  fi
  log "ERROR: cannot write to $dir ($what) as uid=$(id -u) gid=$(id -g)."
  log "  Check PUID/PGID in .env: run 'id' on the NAS (UGREEN UGOS usually needs PGID=10),"
  log "  then rebuild with: docker compose up -d --build"
  log "  Also check the folder's owner and permissions on the NAS."
  exit 1
}
require_writable /data "DATA_DIR"
require_writable "$WORKSPACE" "WORKSPACE_DIR, or DATA_DIR/workspace by default"

umask 077
mkdir -p "$HOME" "$HOME/.ssh" "$HOME/.ssh-host"
chmod 700 "$HOME" "$HOME/.ssh" "$HOME/.ssh-host"
chmod 750 /data 2>/dev/null || true
# The workspace may be a shared NAS folder: leave its permissions alone.

# --- SSH host key (generated once, kept on the volume so the fingerprint stays stable)
if [[ ! -f "$HOME/.ssh-host/ssh_host_ed25519_key" ]]; then
  log "Generating SSH host key"
  ssh-keygen -q -t ed25519 -N '' -f "$HOME/.ssh-host/ssh_host_ed25519_key"
fi

# --- Authorized keys: merge keys from SSH_AUTHORIZED_KEYS (public keys only) into the file
touch "$HOME/.ssh/authorized_keys"
chmod 600 "$HOME/.ssh/authorized_keys"
if [[ -n "${SSH_AUTHORIZED_KEYS:-}" ]]; then
  while IFS= read -r key; do
    key="${key#"${key%%[![:space:]]*}"}"
    [[ -z "$key" || "$key" == \#* ]] && continue
    grep -qxF "$key" "$HOME/.ssh/authorized_keys" || printf '%s\n' "$key" >> "$HOME/.ssh/authorized_keys"
  done <<< "$(printf '%s' "$SSH_AUTHORIZED_KEYS" | tr ';' '\n')"
fi
if [[ ! -s "$HOME/.ssh/authorized_keys" ]]; then
  log "WARNING: no SSH public key configured. Set SSH_AUTHORIZED_KEYS in .env, otherwise SSH login is impossible."
fi

# --- Git identity (only if not set yet)
if [[ -n "${GIT_USER_NAME:-}" ]] && ! git config --global user.name >/dev/null; then
  git config --global user.name "$GIT_USER_NAME"
fi
if [[ -n "${GIT_USER_EMAIL:-}" ]] && ! git config --global user.email >/dev/null; then
  git config --global user.email "$GIT_USER_EMAIL"
fi
git config --global init.defaultBranch >/dev/null || git config --global init.defaultBranch main

# --- Default tmux config (user can edit it on the volume)
[[ -f "$HOME/.tmux.conf" ]] || cp /etc/nas-agent/tmux.conf "$HOME/.tmux.conf"

# --- Workspace instructions for Claude (user can edit)
[[ -f "$WORKSPACE/CLAUDE.md" ]] || cp /etc/nas-agent/workspace-CLAUDE.md "$WORKSPACE/CLAUDE.md" || log "WARNING: could not create $WORKSPACE/CLAUDE.md"

# --- Optional Google service account key: export for the tmux server (Claude, Firebase MCP)
SA_KEY="$HOME/.config/gcloud/service-account.json"
if [[ -f "$SA_KEY" ]]; then
  chmod 600 "$SA_KEY" 2>/dev/null || true
  export GOOGLE_APPLICATION_CREDENTIALS="$SA_KEY"
  log "Using Google service account key $SA_KEY"
fi

# --- tmux: window "claude-server" = agent install + Remote Control supervisor, window "terminal" = plain shell
tmux kill-server 2>/dev/null || true
tmux new-session -d -s main -n claude-server -c "$WORKSPACE" "install-agents.sh --if-missing; exec rc-loop.sh"
tmux new-window -d -t main -n terminal -c "$WORKSPACE"

log "tmux session 'main' started (windows: claude-server, terminal)"
log "Starting sshd on port 2222 (key-only)"
exec /usr/sbin/sshd -D -e -f /etc/nas-agent/sshd_config
