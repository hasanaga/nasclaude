# nasclaude — detailed guide

A Docker setup that runs AI coding agents on a home NAS and lets you drive them from your phone or laptop.

**What's in the container:**
- **Claude Code** in official Remote Control server mode: open and steer sessions from the Claude mobile app or claude.ai/code.
- **Codex CLI**, **GitHub CLI (`gh`)**, **Cloudflare Wrangler**, **Google Cloud CLI (`gcloud`)** and **Firebase CLI** (the Firebase MCP server can be registered in Claude Code with `FIREBASE_MCP=true`).
- **Headless Chromium** (Debian package with all libraries and fonts) for screenshots and browser tests, for example `playwright-core` with `executablePath: process.env.CHROME_PATH`. No browser download needed.
- **tmux**: everything keeps running in the background when you disconnect.
- **SSH**: key-only, port 2222. Full terminal from Termius, Blink or any SSH client.

**Security defaults:**
- Nothing is installed on the NAS itself; all state lives in `DATA_DIR`.
- No Docker socket is mounted.
- The container runs as a non-root user, with no Linux capabilities and a read-only image filesystem.

## How it works

```
Phone: Claude app (Code tab) ──HTTPS (outbound only)──► Anthropic ◄── claude remote-control
Phone/laptop: SSH client ──SSH (LAN or Tailscale)──► :2222 ──► tmux "main"
                                                      ├─ 1 claude-server : Remote Control server (auto-restart)
                                                      └─ 2 terminal      : plain bash (gh, git, codex, ...)
NAS: DATA_DIR ──► /data
       ├─ .home/      logins, agent binaries, gh config, SSH keys
       └─ workspace/  projects (Claude sessions start here)
```

## Requirements
- Docker and SSH access on the NAS.
- For access from outside your home network: Tailscale (for example the NAS's own Tailscale package).
- A Claude **Pro, Max, Team or Enterprise** subscription. Remote Control does not work with an API key.
- On your phone: the **Claude app** (iOS or Android) and an SSH client such as **Termius**.

## Setup

### 1. SSH key
Create an ED25519 key on each device you will connect from (in Termius: **Keychain → Generate Key → ED25519**; on a computer: `ssh-keygen -t ed25519`). You only need the **public** part, the line starting with `ssh-ed25519 AAAA...`. Separate several keys with `;`.

### 2. Get the files onto the NAS
Clone this repository on the NAS (as your normal user, not with `sudo`):
```bash
git clone https://github.com/hasanaga/nasclaude.git /volume1/docker/nasclaude
```

### 3. Configure
```bash
cd /volume1/docker/nasclaude
```
```bash
cp .env.example .env
```
Check your user and group IDs:
```bash
id
```
Fill in `.env`:
- `PUID` and `PGID`: the values printed by `id`. On UGREEN UGOS `PGID` is usually `10` (`admin`), which is also the default in `.env.example`.
- `DATA_DIR`: the data folder.
- `SSH_AUTHORIZED_KEYS`: the public key(s) from step 1.
- `GIT_USER_NAME` and `GIT_USER_EMAIL`: optional.

Create the data folder:
```bash
mkdir -p /volume1/docker/nasclaude/data/workspace
```

### 4. Start
```bash
docker compose up -d --build
```
On first start Claude Code, Codex, Wrangler, gcloud and the Firebase CLI are installed into `DATA_DIR/.home` from their official channels. This can take a few minutes. Follow the progress with:
```bash
docker logs -f nas-agent
```

### 5. First login (once)
Add a host in your SSH client:
- **Address:** the NAS LAN IP or Tailscale IP
- **Port:** `2222`
- **Username:** `agent`
- **Key:** the key from step 1

A **menu** opens on connect. Then:

1. Type `2` to open the `terminal` window.
2. Log in to Claude:
   ```bash
   claude auth login
   ```
   Open the link in a browser, approve, and paste the code back.
3. Log in to GitHub (enables clone, pull and push for private repositories):
   ```bash
   gh auth login
   ```
   ```bash
   gh auth setup-git
   ```
4. Optional logins:
   - **Codex:** `codex login`. If the browser callback does not work headless, use the device-code login described in the Codex docs.
   - **Cloudflare Wrangler:**
     - **API token (easiest in a container):** create a token with the minimum permissions and add `export CLOUDFLARE_API_TOKEN=...` to `~/.bashrc`. Do not put the token in `.env` or git.
     - **`wrangler login`:** the browser login redirects to `localhost:8976`, so connect with port forwarding (`ssh -L 8976:localhost:8976 -p 2222 agent@<NAS-IP>`) and then run `wrangler login`.
   - **Google Cloud and Firebase.** The Firebase MCP server is off by default. To register it in Claude Code, set `FIREBASE_MCP=true` in `.env` and recreate the container (`docker compose up -d`), or add it by hand with `claude mcp add --scope user firebase -- firebase mcp`. Remove it again with `claude mcp remove --scope user firebase`. Logins:
     - With your own account, without a local browser:
       ```bash
       gcloud auth login --no-launch-browser
       ```
       ```bash
       gcloud auth application-default login --no-launch-browser
       ```
       ```bash
       firebase login --no-localhost
       ```
     - With a service account: put the JSON key at `DATA_DIR/.home/.config/gcloud/service-account.json` and restart the container. `GOOGLE_APPLICATION_CREDENTIALS` is then set automatically for the Firebase CLI, the Firebase MCP server and Google client libraries. For `gcloud` itself, activate it once:
       ```bash
       gcloud auth activate-service-account --key-file ~/.config/gcloud/service-account.json
       ```
       A key file is a long-lived secret: grant the service account only the roles it needs and never commit the key.
   - Any of these tools can be skipped with `INSTALL_CODEX`, `INSTALL_WRANGLER`, `INSTALL_GCLOUD` or `INSTALL_FIREBASE` set to `false` in `.env`.
5. Switch to the `claude-server` window (`Ctrl-b 1` or `attach claude-server`). Within 15 seconds the loop restarts `claude remote-control`, which asks two questions the first time. Answer `y` to both:
   - `Enable Remote Control?`
   - `Trust /data/workspace?`
6. Detach with `Ctrl-b d`. Everything keeps running.

### 6. Use it from your phone
In the Claude app, open **Code**. Your NAS session appears in the list (named with the `RC_PREFIX` from `.env`). You can also press space in the `claude-server` window to show a QR code.
- Sessions start in `/data/workspace`.
- To work on a repository, ask Claude, for example: *"clone `owner/repo` and read its README"*. Claude runs `gh repo clone`.

### Push notifications
In a Claude session in the terminal, run `/config` and turn on **Push when Claude decides** and/or **Push when actions required**. Notifications go to the Claude app signed in with the same account.

## Windows, menu and commands

> These commands exist **only inside the container** (SSH on port **2222** as `agent`). The NAS's own SSH (port 22) is only for `docker compose` and updates.

The menu opens automatically when you SSH in:

```
=== NAS Agent ===
Open windows:
   1) * claude-server      claude     /data/workspace
   2)   terminal           bash       /data/workspace
   3)   myrepo             codex      /data/workspace/myrepo

  n) New window
  q) Quit menu (plain shell)

Choose a number or letter:
```

- **Switch to a window:** type its number.
- **New window:** type `n`. If the name matches a folder in the workspace, the window opens there.
- **Plain shell:** type `q`.

The same as commands:

| Command | What it does |
|---|---|
| `menu` | Opens the menu again |
| `new` | Opens a new window |
| `new myrepo` | Opens `myrepo` in `/data/workspace/myrepo`, or switches to it if already open |
| `new name /path` | Opens a window in the given folder |
| `list` | Lists open windows |
| `attach myrepo` or `attach 3` | Attaches to a window by name or number |

- `Tab` completes window and folder names.
- `Ctrl-b d` detaches without stopping anything.
- To stop the menu from opening on login: `touch ~/.no-menu`.
- **Several terminals at once:** every SSH connection (for example every Termius tab) gets its own view. Windows are shared, but each terminal keeps its own active window, so one does not switch the other. Two terminals can also show the same window. A view is removed when its terminal disconnects. This applies when you connect through `menu`, `new` or `attach`; a manual `tmux attach` still joins the shared session.
- **Windows survive restarts and rebuilds:** every 30 seconds the window list (name, folder, whether Claude runs in it) is saved to `DATA_DIR/.home/.local/state/nas-agent/tmux-windows.tsv`. When the container starts again, the windows are recreated in the same folders, and windows that ran Claude start `claude --continue` (with `--remote-control` if it was on), so the last conversation continues. Other running programs (dev servers, Codex) are not restarted, and an unfinished Claude reply is not resumed. Turn it off with `TMUX_RESTORE=false` in `.env`.
- **Same Claude session in the terminal and the app:** in a window, run `claude --remote-control "myrepo"`. The session is interactive in the terminal and also appears in the Claude app.

## Day-to-day

| Task | How |
|---|---|
| Open a terminal | SSH in and pick a window from the menu |
| Update agents and tools | `install-agents.sh` (Claude Code also updates itself) |
| Restart Remote Control | `Ctrl-c` in the `claude-server` window, or `docker restart nas-agent` on the NAS |
| Update the image (gh, Node, system packages) | On the NAS: `git pull`, then `docker compose up -d --build` (open windows are recreated, running programs restart) |
| Logs | On the NAS: `docker logs nas-agent` |

Logins, agents and projects live in `DATA_DIR`, so nothing is lost when the container is recreated.

## A second, independent instance

Each instance lives in its own folder (its own git clone) with its own `.env`, image, data folder and port. Updating, stopping or removing one does not affect the other.

1. Clone the repository into another folder:
   ```bash
   git clone https://github.com/hasanaga/nasclaude.git /volume1/docker/nasclaude-2
   ```
2. Create `.env` (`cp .env.example .env`) with values that **differ** from the first instance:
   ```
   CONTAINER_NAME=nas-agent-2
   DATA_DIR=/volume1/docker/nasclaude-2/data
   SSH_PORT=2223
   RC_PREFIX=nas2
   ```
   `PUID` and `PGID` stay the same.
3. Create the data folder:
   ```bash
   mkdir -p /volume1/docker/nasclaude-2/data/workspace
   ```
4. Start it:
   ```bash
   docker compose up -d --build
   ```

`CONTAINER_NAME` sets the container name, the compose project name and the image tag (`nas-agent-2:local`), so the instances share nothing.

### Sharing projects (`WORKSPACE_DIR`)
Two instances can use the same projects folder while logins and agent installs stay separate in each `DATA_DIR`.

1. Create the shared folder:
   ```bash
   mkdir -p /volume1/docker/shared-workspace
   ```
2. Add the same line to the `.env` of **both** instances:
   ```
   WORKSPACE_DIR=/volume1/docker/shared-workspace
   ```
3. Recreate both containers with `docker compose up -d`.

Notes:
- The folder must exist beforehand. Otherwise the container fails with `bind source path does not exist`, which prevents Docker from creating it as root.
- Two agents changing the same repository at the same time can cause git conflicts. Prefer one repository per instance at a time.
- Existing projects are not moved automatically; copy the contents of `DATA_DIR/workspace` yourself if needed.

## Security
- **Never forward port 2222 on your router.** Use Tailscale for remote access.
- `DATA_DIR/.home` holds your Claude, GitHub, Codex and other logins. Do not share it with other NAS users and do not include it in unencrypted backups.
- Claude can run any command inside `/data` on request from your phone. It cannot see the rest of the NAS.
- Use narrowly scoped tokens (for example fine-grained GitHub tokens).
- Consider enabling **Require trusted devices** in your claude.ai account settings, so Remote Control sessions can only be viewed and steered from enrolled devices.
- While Remote Control is connected, the conversation is stored on Anthropic's servers; code and files stay on the NAS.

## Browser (Chromium)
The image includes Chromium at `/usr/bin/chromium` (`CHROME_PATH` and `PUPPETEER_EXECUTABLE_PATH` point to it; `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1` is set). System packages cannot be installed inside the running container (read-only filesystem, no sudo), which is why it is part of the image.

```js
import { chromium } from "playwright-core";
const browser = await chromium.launch({ executablePath: process.env.CHROME_PATH });
```
- From the command line: `chromium --headless --no-sandbox --screenshot=shot.png https://example.com`.
- The container has no Linux capabilities, so Chromium's own sandbox cannot start: use `--no-sandbox` (Playwright already does this by default).
- `shm_size: 1gb` in `compose.yaml` prevents crashes from Docker's small default `/dev/shm`.
- Set `INSTALL_CHROMIUM=false` in `.env` and rebuild to leave it out (saves about 350 MB).

## Troubleshooting
- **`ERROR: cannot write to /data ...` or `mkdir: cannot create directory '/data'`:** usually a wrong `PGID` in `.env`. Check with `id` on the NAS (on UGOS usually `PGID=10`), then run `docker compose up -d --build`. If that does not help, check the folder's owner and permissions.
- **SSH `Permission denied (publickey)`:** check the key in `.env`, then recreate the container with `docker compose up -d`. Keys are added to `DATA_DIR/.home/.ssh/authorized_keys`. When connecting with OpenSSH, pass the right key with `-i`.
- **Remote Control `must be logged in`:** run `claude auth login` (step 5). Tokens from `claude setup-token` cannot start Remote Control.
- **`ANTHROPIC_API_KEY is set`:** remove the variable; Remote Control needs a subscription login.
- **Server stops after a ~10 minute network outage:** expected in server mode; `rc-loop.sh` restarts it automatically.
