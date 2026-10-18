# PATH for login shells (SSH, tmux windows)
export HOME=/data/.home
export WORKSPACE=/data/workspace
export NPM_CONFIG_PREFIX=/data/.home/.npm-global
case ":$PATH:" in
  *":/data/.home/.local/bin:"*) ;;
  *) export PATH="/data/.home/.local/bin:/data/.home/.npm-global/bin:/data/.home/.local/google-cloud-sdk/bin:$PATH" ;;
esac
export LANG=C.UTF-8 LC_ALL=C.UTF-8

# Optional Google service account key (used by gcloud ADC, Firebase CLI/MCP, client libraries)
if [ -f /data/.home/.config/gcloud/service-account.json ]; then
  export GOOGLE_APPLICATION_CREDENTIALS=/data/.home/.config/gcloud/service-account.json
fi

# tmux helpers (menu / new / list / attach) for interactive bash shells
if [ -n "$BASH_VERSION" ]; then
  case $- in
    *i*) . /etc/nas-agent/tmux-helpers.bash ;;
  esac
fi
