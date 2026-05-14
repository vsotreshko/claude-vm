# README update design

**Date:** 2026-05-14
**Status:** Approved (design phase)
**Author:** Volodymyr Otreshko (via brainstorming session)

## Problem

The current `README.md` has drifted out of date. Since it was written, the project gained:

- `--gh` flag (per-project GitHub PAT auth, persistent volume)
- `--gcloud` flag rename (was `--gcloud-login`) + per-project gcloud volume (was host bind-mount)
- `--resume <id>` flag for resuming Claude sessions
- `claude-docker purge` command
- Shared pnpm content-addressed store volume across all containers
- Monorepo support: walks up to find lock file when defining "project root"
- Credential sync flow for `~/.claude.json` (copy-in / copy-out / fallback chain) to avoid Docker inode staleness
- Host-networking auto-detection (Linux/OrbStack vs Docker Desktop fallback)
- Additional tools preinstalled in the image: `gh`, `ffmpeg`, `uv`, hasura CLI
- Passwordless sudo for the in-container user; `~/.claude` mounted at both `/home/claude/.claude` and the host's absolute `$HOME/.claude` path

The existing README also has factual errors (the isolation table still lists `~/.config/gcloud` as a host bind-mount).

## Goals

- Cold reader on GitHub can understand **what `claude-vm` is, why it exists, and how to install/run it** in under 5 minutes
- All current commands, flags, and integrations are documented
- Mechanism is explained at a **high level** (mounts + one quirky flow), not as bash internals
- Document is a README, **not a manual** — limits depth and scope deliberately
- Tone and visual shape stay consistent with the current README (tables, code blocks, minimal prose)

## Non-goals

- No troubleshooting section, no FAQ, no comparison to alternatives (descoped in brainstorming)
- No architecture diagrams or sequence diagrams
- No deep dive into every Docker volume, every line of `claude-docker`, or every environment variable
- No tutorial-style narrative; the README is reference-leaning

## Audience

Public GitHub readers. Assume:

- Comfortable with the command line
- Familiar with Docker (knows what an image/container/volume is)
- May or may not have used Claude Code before
- Found the repo cold — needs the "what" and "why" before the "how"

## Structure

Tight linear (Option A from brainstorming):

1. Description
2. Why
3. Requirements
4. Quick start
5. How it works
6. Commands & flags
7. Optional integrations
8. Limitations & caveats
9. Cleanup
10. License

Rationale: matches the existing README's shape, lets a cold reader scroll top-to-bottom, keeps mechanism in one place between setup and reference.

## Section contents

### §1 Description

One paragraph. Hook + trade-off framing.

> `claude-vm` runs Claude Code in an isolated Docker container per project. You get `--dangerously-skip-permissions` (full autonomy: file edits, package installs, command execution) without that autonomy reaching the rest of your machine. One command, one container per project, your existing Claude session and credentials come along.

### §2 Why

Bullet list. Frames the autonomy/safety trade-off and lists the four key choices.

- Claude Code is most useful with `--dangerously-skip-permissions`, but giving that to a host shell is risky (it can `rm`, push, install globally, leak SSH keys, etc.)
- Solution: dedicated Docker container per project, only that project mounted
- Credentials (`~/.claude`, `~/.claude.json`) shared so no re-login; sessions resumable
- Optional, opt-in passthrough for git config, SSH (read-only), gcloud, GitHub PAT

### §3 Requirements

- macOS (Apple Silicon or Intel) or Linux
- [Docker Desktop](https://docs.docker.com/get-docker/) or [OrbStack](https://orbstack.dev/) (OrbStack recommended on macOS — host networking works)

The OrbStack note matters because of the `--network host` fallback. Flagged here, not buried in caveats.

### §4 Quick start

Install:

```bash
git clone https://github.com/vsotreshko/claude-vm
cd claude-vm
make install
```

Use:

```bash
cd ~/my-project
claude-docker
```

On first run:

1. Builds the Docker image (Node LTS + `git`, `gh`, `gcloud`, `ffmpeg`, `uv`, Claude Code, Playwright MCP)
2. Creates a container scoped to this project; mounts the project at its absolute host path
3. Brings your Claude setup along: mounts `~/.claude` (settings, agents, hooks, session history) and copies `~/.claude.json` (credentials + per-project state) into the container — no re-login, conversations continue
4. Installs dependencies (`pnpm`/`yarn`/`npm` auto-detected, walks up to find lock file for monorepos)
5. Launches Claude Code with `--dangerously-skip-permissions`

Re-running `claude-docker` in the same directory attaches to the existing container and starts a fresh Claude session. Different directories → separate containers.

> `~/.claude.json` is **copied** (not bind-mounted) to avoid Docker inode-staleness when Claude rewrites it. Container writes are synced back to host on exit. Details in §5.

### §5 How it works

#### What the container can see

| What | How |
|---|---|
| Current project (walks up to monorepo root via lock file) | Bind-mounted read/write at the same absolute path as on host |
| `~/.claude` (settings, agents, hooks, history) | Bind-mounted read/write at **both** `/home/claude/.claude` and the host's `$HOME/.claude` path (so Claude finds it whether it looks at `$HOME` or absolute paths stored in session files) |
| `~/.claude.json` (credentials, per-project state) | Copied in at start, synced back on exit (see below) |
| `~/.gitconfig` | Bind-mounted read-only (if exists) |
| `~/.ssh` | Bind-mounted read-only (if exists) |
| `~/.config/gcloud` | Per-project Docker volume, initialized with `--gcloud` |
| GitHub auth | Per-project Docker volume, initialized with `--gh` |
| `node_modules` | Per-project named Docker volume (Linux-native binaries) |
| pnpm content-addressed store | Single Docker volume shared by all `claude-docker` containers |
| Rest of your home folder | Not visible |
| Host network | `--network host` on Linux/OrbStack; `host.docker.internal` + `/etc/hosts` forwarding elsewhere |

> **`--gcloud` / `--gh` are opt-in once.** First run with the flag creates and populates the per-project volume. Every subsequent run auto-mounts that volume — no flag needed — until you `claude-docker clean` or `purge`.

#### Credential sync (`~/.claude.json`)

Claude Code rewrites this file frequently. Bind-mounting it across the Docker boundary causes inode staleness — host edits stop being visible inside the container, and vice-versa. Instead:

- **Start:** host's `~/.claude.json` → copied into container
- **Exit:** container's copy → written to `~/.claude/.claude.json.shared` (carried out via the bind-mounted `~/.claude`) → copied back to host's `~/.claude.json`
- **Fallback chain** if host file missing: `~/.claude/.claude.json.shared` → most recent backup under `~/.claude/backups/`

Net effect: same conversation history and credentials inside and outside the container, no manual sync, no stale-inode breakage.

### §6 Commands & flags

**Commands**

| Command | What it does |
|---|---|
| `claude-docker` | Launch (or attach to) Claude Code for the current project |
| `claude-docker shell` | Open a bash shell inside the running container |
| `claude-docker status` | Show container info and mounts |
| `claude-docker list` | List all running `claude-docker` containers |
| `claude-docker stop` | Stop this project's container |
| `claude-docker clean` | Remove this project's container + volumes (`node_modules`, `gcloud`, `gh`) |
| `claude-docker purge` | **Delete all** `claude-docker` containers and volumes across every project (interactive confirm) |
| `claude-docker update` | Rebuild the Docker image with `--no-cache` |
| `claude-docker help` | Show help |

**Flags** (placed before the command)

| Flag | What it does |
|---|---|
| `--gcloud` | Initialize per-project gcloud auth on first run; auto-mounted thereafter |
| `--gh` | Prompt for a fine-grained GitHub PAT and configure `gh` for this project; auto-mounted thereafter |
| `--resume <id>` | Resume a previous Claude session by ID |

### §7 Optional integrations

Four mini-sections.

#### gcloud (`--gcloud`)

Per-project gcloud auth so projects can't see each other's credentials.

```bash
claude-docker --gcloud        # first run: runs `gcloud auth login --no-launch-browser`
claude-docker                 # subsequent runs: gcloud volume auto-mounted
```

Runs both `gcloud auth login` and `gcloud auth application-default login`. Credentials live in a Docker volume named `claude-docker-gcloud-<project>`. Removed by `claude-docker clean`.

#### GitHub (`--gh`)

Per-project GitHub auth via fine-grained PAT — scoped to whichever repos you select when creating the token, so the container only sees what it needs.

```bash
claude-docker --gh            # prompts for a PAT, runs `gh auth login --with-token`
```

The prompt includes a link to GitHub's token-creation page pre-filled with a sensible description. Token is piped to `gh` and immediately unset from the shell. `gh auth setup-git` is attempted (best-effort; `~/.gitconfig` is read-only inside the container, so configure on the host if needed). Auto-mounted on subsequent runs.

#### Resume a session (`--resume`)

```bash
claude-docker --resume <session-id>
```

Forwarded to `claude --resume`. Works both on first run and when attaching to an already-running container.

#### Playwright MCP

The Docker image preinstalls `@playwright/mcp` and a matching Chromium browser. Two flags are required for it to work inside Docker; they're harmless on macOS too, so the same config works in both places. Add to `~/.claude.json` under the global `mcpServers` key:

```json
{
  "mcpServers": {
    "playwright": {
      "type": "stdio",
      "command": "npx",
      "args": ["@playwright/mcp@latest", "--no-sandbox", "--ignore-https-errors"],
      "env": {}
    }
  }
}
```

| Flag | Why |
|---|---|
| `--no-sandbox` | Chromium sandboxing doesn't work inside Docker |
| `--ignore-https-errors` | Allow self-signed certificates |

> **Project-level overrides:** if `~/.claude.json` has a project-level `mcpServers.playwright` entry under your project's path key, it overrides the global one. Add the same flags there or remove the project entry.

### §8 Limitations & caveats

- **macOS and Linux only.** Windows untested. Apple Silicon and Intel both work.
- **Docker Desktop on macOS loses host networking.** `--network host` is unsupported there, so services on the host must be reached via `host.docker.internal` instead of `localhost`. OrbStack supports host networking and is the smoother choice on macOS.
- **One container per project root.** "Project root" is the nearest ancestor with a lockfile (`pnpm-lock.yaml`, `package-lock.json`, `yarn.lock`, or `pnpm-workspace.yaml`). Working in two subdirectories of the same monorepo shares a container; two different repos get two containers.
- **`node_modules` lives in a Docker volume**, not on the host. Host-side IDE features that rely on `node_modules` (type lookups, ESLint resolution) won't see them. Install on the host too if you need that.
- **`~/.claude.json` is copied, not bind-mounted.** Concurrent edits inside and outside the container during a session can race; the last writer on exit wins. In practice a single host session + a single container session is fine.
- **`~/.gitconfig` and `~/.ssh` are read-only** inside the container. Tools that try to write them (`gh auth setup-git`, `ssh-keygen`) will fail; configure on the host.
- **gcloud / gh / pnpm-store volumes persist** until `claude-docker clean` (per project) or `claude-docker purge` (all). They are not garbage-collected automatically.
- **Image is ~3-4 GB.** Node LTS + Chromium + gcloud SDK + gh + ffmpeg + uv. First `make install` then first `claude-docker` is slow; everything after is fast.
- **Container runs as your host UID with passwordless sudo.** Inside the container Claude can do anything root can — `apt-get install`, `chmod`, etc. The isolation guarantee is that "anything" stops at the container boundary, not that Claude is unprivileged inside.

### §9 Cleanup

```bash
claude-docker clean              # this project's container + volumes (node_modules, gcloud, gh)
claude-docker purge              # ALL claude-docker containers + volumes across every project (interactive)
docker rmi claude-code-sandbox   # remove the image itself
```

> `purge` also removes the shared pnpm store volume — the next `pnpm install` in any project will refill it from scratch.

### §10 License

MIT

## Out of scope (explicitly)

- Troubleshooting section
- FAQ
- Comparison to devcontainers / other sandboxes
- Architecture or sequence diagrams
- Contributing guide
- Repo-structure tree (was in old README; adds little value to a cold reader and is one more thing to keep updated)

## Acceptance criteria

- All current `claude-docker` commands, flags, and integrations appear somewhere in the README
- Mounts table matches the actual behavior of `claude-docker` as of 2026-05-14
- No reference to the removed `--gcloud-login` flag or to gcloud as a host bind-mount
- `purge`, `--gh`, `--resume`, shared pnpm store, monorepo lock-file walk-up, host-networking detection, and credential-sync flow are each documented
- Document does not exceed ~250 lines of Markdown (lightweight, README-shaped, not a manual)
