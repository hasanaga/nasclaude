# nas-agent: Claude Code (Remote Control server mode) + tools in tmux, SSH-only terminal access.
# Agents are NOT baked into the image: they are installed on first start into /data/.home
# with their official installers, so they persist and self-update independently of the image.
FROM node:22-bookworm-slim

ARG PUID=1000
ARG PGID=1000
ARG USERNAME=agent

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# Base tools. gh comes from GitHub's official apt repository.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      bash ca-certificates curl git gnupg less jq nano openssh-client openssh-server \
      procps python3 ripgrep tini tmux tzdata unzip; \
    install -d -m 0755 /etc/apt/keyrings; \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /etc/apt/keyrings/githubcli-archive-keyring.gpg; \
    chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg; \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends gh; \
    rm -rf /var/lib/apt/lists/*; \
    rm -f /etc/ssh/ssh_host_*

# Optional headless Chromium (Debian package, with all shared libraries and fonts) for
# screenshots and browser testing, e.g. playwright-core with executablePath=$CHROME_PATH.
# Packages cannot be installed at runtime (read-only root, no sudo), so it lives in the image.
ARG INSTALL_CHROMIUM=true
RUN set -eux; \
    if [ "$INSTALL_CHROMIUM" = "true" ]; then \
      apt-get update; \
      apt-get install -y --no-install-recommends chromium fonts-liberation fonts-noto-color-emoji; \
      rm -rf /var/lib/apt/lists/*; \
    fi

# The node base image ships a "node" user with UID/GID 1000; replace it with ours.
# HOME lives on the persistent volume.
RUN set -eux; \
    userdel -r node 2>/dev/null || true; \
    groupdel node 2>/dev/null || true; \
    groupadd -g "${PGID}" "${USERNAME}" 2>/dev/null || true; \
    useradd -u "${PUID}" -g "${PGID}" -d /data/.home -M -s /bin/bash "${USERNAME}"; \
    install -d -m 0755 /run/sshd

# COPY carries the build context's permissions onto existing dirs like /usr and /etc.
# A NAS checkout can have restrictive modes (e.g. 700), so normalise them explicitly.
COPY rootfs/ /
RUN set -eux; \
    chmod 0755 / /etc /etc/nas-agent /etc/profile.d /usr /usr/local /usr/local/bin; \
    chmod 0644 /etc/nas-agent/* /etc/profile.d/nas-agent.sh; \
    chmod 0755 /usr/local/bin/*

ENV CHROME_PATH=/usr/bin/chromium \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium \
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1

ENV HOME=/data/.home \
    WORKSPACE=/data/workspace \
    NPM_CONFIG_PREFIX=/data/.home/.npm-global \
    PATH=/data/.home/.local/bin:/data/.home/.npm-global/bin:/data/.home/.local/google-cloud-sdk/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

USER ${PUID}:${PGID}
WORKDIR /data/workspace
EXPOSE 2222

HEALTHCHECK --interval=60s --timeout=5s --start-period=30s --retries=3 \
  CMD pgrep -x sshd >/dev/null && tmux has-session -t main 2>/dev/null

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
