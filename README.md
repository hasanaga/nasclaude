# nasclaude

Run Claude Code on your own NAS or home server, and control it from your phone.

Your NAS keeps working on your code around the clock. You start tasks, follow progress and answer questions from the Claude app on your phone, or open a full terminal over SSH when you need one. Code and files never leave your machine.

## What you can do with it

- **Code from your phone.** Ask Claude to fix a bug, write a feature or review a repository while you are away from your computer. It runs on the NAS, not on your phone.
- **Keep long tasks running.** Close the app or lose the connection; the work continues on the NAS. Claude can send a push notification when it is done or needs you (enable it once with `/config`).
- **Use one always-on machine for everything.** Clone your GitHub repositories once, keep logins and tools in one place, and reach them from your phone, tablet or laptop.
- **Jump into a terminal when needed.** SSH in from Termius, Blink or any SSH client and use `git`, `gh`, Codex and other CLIs side by side with Claude.

## Where it runs

Any always-on machine with Docker (x86_64 or arm64, 4 GB RAM or more):

- a NAS (tested on UGREEN; Synology, QNAP, TrueNAS and Unraid should work the same way)
- a home server or mini PC
- a Linux VM or VPS

For access from outside your home network, use [Tailscale](https://tailscale.com) or another VPN. Do not open the SSH port to the internet.

## What's inside

- **Claude Code** with [Remote Control](https://code.claude.com/docs/en/remote-control), always on and restarted automatically
- **Codex CLI, GitHub CLI, Cloudflare Wrangler, Google Cloud CLI, Firebase CLI** (Firebase MCP server optional), each optional
- **Headless Chromium** for screenshots and browser tests
- **tmux** with a simple menu, so nothing stops when you disconnect; windows and Claude conversations come back after a restart or update
- **Key-only SSH** on port 2222

The container runs as a normal user, with a read-only system, no extra privileges and no access to the Docker socket. All your data lives in one folder.

## Requirements

- Docker with Compose
- A Claude **Pro, Max, Team or Enterprise** plan (Remote Control does not work with an API key)
- The Claude app on your phone ([iOS](https://apps.apple.com/us/app/claude-by-anthropic/id6473753684), [Android](https://play.google.com/store/apps/details?id=com.anthropic.claude)) and, optionally, an SSH client

## Install

**1. Get the code** (on the NAS, over SSH):
```bash
git clone https://github.com/hasanaga/nasclaude.git && cd nasclaude
```

**2. Configure:**
```bash
cp .env.example .env && mkdir -p data/workspace && id
```
Open `.env` and set:
- `DATA_DIR`: the full path of the `data` folder you just created
- `PUID` / `PGID`: the numbers shown by `id`
- `SSH_AUTHORIZED_KEYS`: your SSH **public** key (`ssh-ed25519 AAAA...`)

**3. Start:**
```bash
docker compose up -d --build
```
The first start installs the tools and takes a few minutes.

**4. Log in once.** Connect with SSH (port `2222`, user `agent`). A menu opens; press `2` for a terminal and run:
```bash
claude auth login
```
Optionally also `gh auth login` for private GitHub repositories. Then press `Ctrl-b 1`, answer `y` to the two Remote Control questions, and detach with `Ctrl-b d`.

**5. Use it.** Open the Claude app, go to **Code**, and pick your NAS session.

## Learn more

The [detailed guide](docs/guide.md) covers tool logins (Codex, Wrangler, gcloud, Firebase), the tmux menu and commands, running several instances, sharing a projects folder, browser testing, security notes and troubleshooting.

## License

[MIT](LICENSE)
