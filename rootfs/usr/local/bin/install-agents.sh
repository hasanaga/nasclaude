#!/usr/bin/env bash
# Installs / updates agent CLIs and tools (Claude Code, Codex, Wrangler, gcloud, Firebase) into $HOME (persistent volume) using their official channels.
#   install-agents.sh             install or update everything
#   install-agents.sh --if-missing  install only what is not present yet
set -uo pipefail

only_missing=false
[[ "${1:-}" == "--if-missing" ]] && only_missing=true

install_claude() {
  if $only_missing && command -v claude >/dev/null; then return 0; fi
  if command -v claude >/dev/null; then
    echo "==> Updating Claude Code"
    claude update
  else
    echo "==> Installing Claude Code (official native installer)"
    curl -fsSL https://claude.ai/install.sh | bash
  fi
}

install_codex() {
  [[ "${INSTALL_CODEX:-true}" == "true" ]] || return 0
  if $only_missing && command -v codex >/dev/null; then return 0; fi
  echo "==> Installing/updating Codex CLI (npm: @openai/codex)"
  npm install -g @openai/codex@latest
}

install_wrangler() {
  [[ "${INSTALL_WRANGLER:-true}" == "true" ]] || return 0
  if $only_missing && command -v wrangler >/dev/null; then return 0; fi
  echo "==> Installing/updating Cloudflare Wrangler (npm: wrangler)"
  npm install -g wrangler@latest
}

install_gcloud() {
  [[ "${INSTALL_GCLOUD:-true}" == "true" ]] || return 0
  if command -v gcloud >/dev/null; then
    $only_missing && return 0
    echo "==> Updating Google Cloud CLI"
    gcloud components update --quiet
    return
  fi
  local arch
  case "$(uname -m)" in
    x86_64) arch=x86_64 ;;
    aarch64|arm64) arch=arm ;;
    *) echo "!! gcloud: unsupported architecture $(uname -m)"; return 1 ;;
  esac
  echo "==> Installing Google Cloud CLI (official tarball, linux-$arch)"
  mkdir -p "$HOME/.local"
  curl -fsSL "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-${arch}.tar.gz" |
    tar -xz -C "$HOME/.local" || return 1
  "$HOME/.local/google-cloud-sdk/install.sh" --quiet --usage-reporting false \
    --path-update false --command-completion false
}

install_firebase() {
  [[ "${INSTALL_FIREBASE:-true}" == "true" ]] || return 0
  if ! $only_missing || ! command -v firebase >/dev/null; then
    echo "==> Installing/updating Firebase CLI (npm: firebase-tools)"
    npm install -g firebase-tools@latest || return 1
  fi
  # Register the Firebase MCP server for Claude Code (user scope, once).
  if command -v claude >/dev/null && ! claude mcp get firebase >/dev/null 2>&1; then
    echo "==> Registering Firebase MCP server in Claude Code"
    claude mcp add --scope user firebase -- firebase mcp
  fi
}

install_claude || echo "!! Claude Code install failed (check network). Retry later: install-agents.sh"
install_codex  || echo "!! Codex install failed (check network). Retry later: install-agents.sh"
install_wrangler || echo "!! Wrangler install failed (check network). Retry later: install-agents.sh"
install_gcloud || echo "!! gcloud install failed (check network). Retry later: install-agents.sh"
install_firebase || echo "!! Firebase CLI install failed (check network). Retry later: install-agents.sh"

echo
command -v claude >/dev/null && echo "claude: $(claude --version 2>/dev/null)"
command -v codex  >/dev/null && echo "codex:  $(codex --version 2>/dev/null)"
command -v wrangler >/dev/null && echo "wrangler: $(wrangler --version 2>/dev/null | tail -1)"
command -v gcloud >/dev/null && echo "gcloud: $(gcloud --version 2>/dev/null | head -1)"
command -v firebase >/dev/null && echo "firebase: $(firebase --version 2>/dev/null)"
command -v gh     >/dev/null && echo "gh:     $(gh --version 2>/dev/null | head -1)"
exit 0
