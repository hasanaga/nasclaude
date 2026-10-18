#!/usr/bin/env bash
# Save and restore the windows of the tmux "main" session across container rebuilds.
# Running processes cannot survive a new container, but window names, folders and
# Claude conversations can: windows that ran Claude get `claude --continue` again,
# and windows that ran a `claude remote-control` server start that server again.
#   tmux-state.sh save      write the current windows to the state file
#   tmux-state.sh restore   recreate saved windows (run once at container start)
#   tmux-state.sh loop      save every TMUX_STATE_INTERVAL seconds (default 30)
set -uo pipefail

SESSION=main
STATE_DIR="${HOME}/.local/state/nas-agent"
STATE="${STATE_DIR}/tmux-windows.tsv"
WS="${WORKSPACE:-/data/workspace}"
# Windows created by the entrypoint itself; never saved or restored.
SKIP_RE='^(claude-server|terminal)$'

# Print what Claude Code runs below the given pane PID:
#   "claude"              interactive session
#   "claude-rc"           interactive session with --remote-control
#   "rc-server<TAB>ARGS"  `claude remote-control` server, with its flags (minus resume flags)
claude_kind() {
  local root="$1"
  ps -eo pid=,ppid=,args= | awk -v root="$root" '
    { pid[NR]=$1; ppid[NR]=$2; $1=""; $2=""; sub(/^ +/, ""); args[NR]=$0 }
    END {
      want[root]=1; changed=1
      while (changed) { changed=0
        for (i=1;i<=NR;i++) if ((ppid[i] in want) && !(pid[i] in want)) { want[pid[i]]=1; changed=1 } }
      for (i=1;i<=NR;i++) if ((pid[i] in want) && pid[i]!=root && args[i] ~ /(^|[ \/])claude( |$)/) {
        n = split(args[i], w, " "); server = 0; out = ""
        for (j=1;j<=n;j++) {
          if (!server) { if (w[j] == "remote-control") server = 1; continue }
          if (w[j] == "-c" || w[j] == "--continue") continue
          if (w[j] == "--session-id") { j++; continue }
          out = out (out == "" ? "" : " ") w[j]
        }
        if (server) { print "rc-server\t" out; exit }
        if (args[i] ~ /--remote-control|--rc( |$)/) { print "claude-rc"; exit }
        print "claude"; exit
      }
    }'
}

save() {
  tmux has-session -t "$SESSION" 2>/dev/null || return 0
  mkdir -p "$STATE_DIR"
  local tmp="${STATE}.tmp.$$" line idx name path ppid auto kind
  : > "$tmp"
  while IFS=$'\t' read -r idx name path ppid; do
    [[ "$name" =~ $SKIP_RE ]] && continue
    auto="$(tmux show-window-options -t "$SESSION:$idx" -v automatic-rename 2>/dev/null)"
    kind="$(claude_kind "$ppid")"
    # kind may already carry a tab and the server flags as a fifth column
    printf '%s\t%s\t%s\t%s\n' "$name" "$path" "${auto:-on}" "${kind:-}" >> "$tmp"
  done < <(tmux list-windows -t "$SESSION" -F '#{window_index}	#{window_name}	#{pane_current_path}	#{pane_pid}')
  mv -f "$tmp" "$STATE"
}

restore() {
  [[ -s "$STATE" ]] || return 0
  tmux has-session -t "$SESSION" 2>/dev/null || return 0
  local name path auto kind rcargs args idx n=0
  while IFS=$'\t' read -r name path auto kind rcargs; do
    [[ -z "$name" || "$name" =~ $SKIP_RE ]] && continue
    [[ -d "$path" ]] || path="$WS"
    args=(-d -t "$SESSION:" -c "$path" -P -F '#{window_index}')
    [[ "$auto" == "off" ]] && args+=(-n "$name")
    idx="$(tmux new-window "${args[@]}")" || continue
    case "$kind" in
      claude)    tmux send-keys -t "$SESSION:$idx" 'claude --continue' Enter ;;
      claude-rc) tmux send-keys -t "$SESSION:$idx" "claude --continue --remote-control $(printf '%q' "$name")" Enter ;;
      # Restarting the server in the same folder brings back its sessions (for ~4 hours).
      rc-server) tmux send-keys -t "$SESSION:$idx" "claude remote-control${rcargs:+ $rcargs}" Enter ;;
    esac
    n=$((n + 1))
  done < "$STATE"
  echo "[tmux-state] restored $n window(s) from $STATE"
}

loop() {
  local interval="${TMUX_STATE_INTERVAL:-30}"
  while sleep "$interval"; do save; done
}

case "${1:-}" in
  save) save ;;
  restore) restore ;;
  loop) loop ;;
  *) echo "usage: $0 save|restore|loop" >&2; exit 2 ;;
esac
