# User-friendly tmux helpers for the "main" session (interactive bash only).
#   menu                 interactive menu: pick a window or open a new one
#   new [name] [dir]     open a new window and switch to it
#   list                 show open windows
#   attach [name|number] attach / switch to an existing window
# The menu opens automatically on SSH login (disable: touch ~/.no-menu).
#
# Every SSH connection gets its own "view" session grouped with "main": all views share
# the same windows, but each one keeps its own active window, so two terminals (e.g. two
# Termius tabs) do not switch each other. A view is removed when its terminal detaches.

_NA_SESSION=main
_NA_WS="${WORKSPACE:-/data/workspace}"

_na_has_session() { tmux has-session -t "$_NA_SESSION" 2>/dev/null; }

_na_ensure_session() {
  _na_has_session || tmux new-session -d -s "$_NA_SESSION" -n terminal -c "$_NA_WS"
}

# Attach this terminal through its own view session; optionally select a window first.
_na_attach_view() {
  local view="view-$$-$RANDOM" s
  # Remove views left behind by terminals that never attached.
  for s in $(tmux list-sessions -F '#{session_name} #{session_attached}' 2>/dev/null | awk '$1 ~ /^view-/ && $2 == 0 { print $1 }'); do
    tmux kill-session -t "$s" 2>/dev/null
  done
  tmux new-session -d -t "$_NA_SESSION" -s "$view" || return 1
  [[ -n "${1:-}" ]] && tmux select-window -t "$view:$1"
  # destroy-unattached must be set only once attached, otherwise tmux drops the view at once.
  tmux attach-session -t "$view" \; set-option -t "$view" destroy-unattached on
}

# The session this terminal is looking at: its own view inside tmux, "main" outside.
_na_current_session() {
  local s=""
  if [[ -n "${TMUX:-}" ]]; then
    s="$(tmux display-message -p '#{client_session}' 2>/dev/null)"
    [[ -n "$s" ]] || s="$(tmux display-message -p '#{session_name}' 2>/dev/null)"
  fi
  echo "${s:-$_NA_SESSION}"
}

# Inside tmux: switch this terminal's window. Outside: attach a new view on that window.
_na_go() {
  if [[ -n "${TMUX:-}" ]]; then
    tmux select-window -t "$(_na_current_session):$1"
  else
    _na_attach_view "$1"
  fi
}

_na_window_exists() {
  tmux list-windows -t "$_NA_SESSION" -F '#{window_index}	#{window_name}' 2>/dev/null |
    awk -F'\t' -v w="$1" '$1 == w || $2 == w { found = 1 } END { exit !found }'
}

_na_print_windows() {
  tmux list-windows -t "$(_na_current_session)" \
    -F '#{window_index}	#{?window_active,*, }	#{window_name}	#{pane_current_command}	#{pane_current_path}' |
    awk -F'\t' '{ printf "  %2s) %s %-18s %-10s %s\n", $1, $2, $3, $4, $5 }'
}

new() {
  local name="${1:-}" dir="${2:-}"
  if [[ -z "$dir" ]]; then
    if [[ -n "$name" && -d "$_NA_WS/$name" ]]; then dir="$_NA_WS/$name"; else dir="$_NA_WS"; fi
  fi
  if [[ ! -d "$dir" ]]; then
    echo "Folder not found: $dir" >&2
    return 1
  fi
  if [[ -n "$name" ]] && _na_window_exists "$name"; then
    echo "Window \"$name\" is already open, switching to it."
    _na_go "$name"
    return
  fi
  _na_ensure_session
  local args=(-d -t "$_NA_SESSION:" -c "$dir" -P -F '#{window_index}')
  [[ -n "$name" ]] && args+=(-n "$name")
  local idx
  idx="$(tmux new-window "${args[@]}")" || return 1
  _na_go "$idx"
}

list() {
  if ! _na_has_session; then
    echo "No open windows. Open one with: new <name>"
    return 1
  fi
  echo "Open windows (* = active):"
  _na_print_windows
}

attach() {
  if ! _na_has_session; then
    echo "No open windows. Open one with: new <name>"
    return 1
  fi
  if [[ -z "${1:-}" ]]; then
    if [[ -n "${TMUX:-}" ]]; then
      echo "You are already inside tmux. Which window do you want?"
      list
      echo "Example: attach 2   or   attach myrepo"
      return
    fi
    _na_attach_view
    return
  fi
  if ! _na_window_exists "$1"; then
    echo "No window named or numbered \"$1\"." >&2
    list
    return 1
  fi
  _na_go "$1"
}

menu() {
  local choice name
  while true; do
    echo
    echo "=== NAS Agent ==="
    if _na_has_session; then
      echo "Open windows:"
      _na_print_windows
    else
      echo "No open windows."
    fi
    echo
    echo "  n) New window"
    echo "  q) Quit menu (plain shell)"
    echo
    read -r -p "Choose a number or letter: " choice || return
    case "$choice" in
      q|Q|"") return ;;
      n|N)
        read -r -p "Window name (a folder name in the workspace opens it there; may be empty): " name || return
        new "$name" && return
        ;;
      *)
        if _na_window_exists "$choice"; then
          _na_go "$choice"
          return
        fi
        echo "No such option: $choice"
        ;;
    esac
  done
}

# Tab completion
_na_complete_windows() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  mapfile -t COMPREPLY < <(compgen -W "$(tmux list-windows -t "$_NA_SESSION" -F '#{window_name}' 2>/dev/null)" -- "$cur")
}
_na_complete_workspace() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  [[ $COMP_CWORD -eq 1 ]] || return
  mapfile -t COMPREPLY < <(cd "$_NA_WS" 2>/dev/null && compgen -d -- "$cur")
}
complete -F _na_complete_windows attach
complete -F _na_complete_workspace new

# On SSH login (outside tmux) open the menu automatically.
if [[ -z "${TMUX:-}" && -n "${SSH_CONNECTION:-}" && ! -e "$HOME/.no-menu" ]]; then
  menu
  echo "Commands: menu | new <name> | list | attach <name|number>"
fi
