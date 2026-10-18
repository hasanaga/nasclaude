# NAS workspace

This directory (`/data/workspace`) is the root workspace on a home NAS. Sessions started from the Claude app open here.

## Conventions
- Each project lives in its own subfolder: `/data/workspace/<repo-name>`.
- To start work on a GitHub repo, clone it here with `gh repo clone <owner>/<repo>` (or `git clone`), then `cd` into it and read its own CLAUDE.md / README before changing anything.
- To start a new project, create a new subfolder and run `git init` inside it.
- `gh` is authenticated for the NAS owner; use it for repo listing, cloning, PRs and issues.
- Never delete project folders or force-push without explicit confirmation from the user.
- Do not touch `/data/.home` (credentials and tool installs live there).
