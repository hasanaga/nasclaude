#!/usr/bin/env bash
# Keeps `claude remote-control` (server mode) running. If it exits (network loss, crash,
# not logged in yet) it waits and starts again; restarting in the same directory brings
# back the sessions the previous server was serving (see Claude Code Remote Control docs).
set -u

cd "${WORKSPACE:-/data/workspace}"

if [[ -n "${ANTHROPIC_API_KEY:-}" || -n "${ANTHROPIC_AUTH_TOKEN:-}" ]]; then
  echo "!! ANTHROPIC_API_KEY / ANTHROPIC_AUTH_TOKEN is set. Remote Control requires a claude.ai subscription login."
fi

delay="${RC_RESTART_DELAY:-15}"

while true; do
  if ! command -v claude >/dev/null; then
    echo "Claude Code is not installed yet. Run: install-agents.sh  (retrying in 60s)"
    sleep 60
    continue
  fi

  args=(remote-control --spawn "${RC_SPAWN:-same-dir}" --capacity "${RC_CAPACITY:-8}")
  [[ -n "${RC_PREFIX:-}" ]] && args+=(--remote-control-session-name-prefix "$RC_PREFIX")

  echo "==> $(date '+%F %T') starting: claude ${args[*]}"
  claude "${args[@]}"
  code=$?

  echo
  echo "==> $(date '+%F %T') claude remote-control exited (code $code). Restarting in ${delay}s."
  echo "    First run? In the 'terminal' window run: claude auth login   (or: claude, then /login)"
  echo "    Press Ctrl-C now to stop the loop (this window then closes)."
  sleep "$delay"
done
