# claude-vm

Run [Claude Code](https://docs.anthropic.com/en/docs/claude-code) in an isolated Docker container, one per project. Full autonomy inside the container, zero risk to the rest of your machine.

## Why

Claude Code is most useful with `--dangerously-skip-permissions` (file edits, package installs, command execution with no prompts). Granting that to a host shell is risky — it can `rm`, push, install globally, leak SSH keys. This project solves it by:

- Running Claude inside a **dedicated Docker container per project**
- Mounting **only that project** — the container can't see the rest of your machine
- **Sharing credentials and session history** so you don't re-log in and conversations continue
- **Opt-in passthrough** for git config, SSH (read-only), gcloud, and GitHub PAT

## Requirements

- macOS (Apple Silicon or Intel) or Linux
- [Docker Desktop](https://docs.docker.com/get-docker/) or [OrbStack](https://orbstack.dev/)

> OrbStack is recommended on macOS — host networking (`--network host`) is unsupported under Docker Desktop on Mac/Windows.

## Quick start

```bash
git clone https://github.com/vsotreshko/claude-vm
cd claude-vm
make install
```

```bash
cd ~/my-project
claude-docker
```

On first run, `claude-docker` will:

1. Build the Docker image (Node LTS + `git`, `gh`, `gcloud`, `ffmpeg`, `uv`, `hasura`, Claude Code, Playwright MCP)
2. Create a container scoped to this project; mount the project at its absolute host path
3. Bring your Claude setup along — mount `~/.claude` (settings, agents, hooks, session history) and copy `~/.claude.json` (credentials + per-project state) into the container — no re-login, conversations continue
4. Install dependencies (`pnpm` / `yarn` / `npm` auto-detected; walks up to find the lock file for monorepos)
5. Launch Claude Code with `--dangerously-skip-permissions`

Re-running `claude-docker` in the same directory attaches to the existing container and starts a fresh Claude session. Different directories → separate containers.

> `~/.claude.json` is **copied** (not bind-mounted) to avoid Docker inode staleness when Claude rewrites it. Container writes are synced back to host on exit. See [How it works](#how-it-works).

## How it works

### What the container can see

| What                                                      | How                                                                                                                                                                                       |
| --------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Current project (walks up to monorepo root via lock file) | Bind-mounted read/write at the same absolute path as on host                                                                                                                              |
| `~/.claude` (settings, agents, hooks, history)            | Bind-mounted read/write at **both** `/home/claude/.claude` and the host's `$HOME/.claude` path (so Claude finds it whether it looks at `$HOME` or absolute paths stored in session files) |
| `~/.claude.json` (credentials, per-project state)         | Copied in at start, synced back on exit (see below)                                                                                                                                       |
| `~/.gitconfig`                                            | Bind-mounted read-only (if exists)                                                                                                                                                        |
| `~/.ssh`                                                  | Bind-mounted read-only (if exists)                                                                                                                                                        |
| `~/.config/gcloud`                                        | Per-project Docker volume, initialized with `--gcloud`                                                                                                                                    |
| GitHub auth                                               | Per-project Docker volume, initialized with `--gh`                                                                                                                                        |
| `node_modules`                                            | Per-project named Docker volume (so Linux-native binaries work)                                                                                                                           |
| pnpm content-addressed store                              | Single Docker volume shared by all `claude-docker` containers                                                                                                                             |
| Rest of your home folder                                  | Not visible                                                                                                                                                                               |
| Host network                                              | `--network host` on Linux/OrbStack; `host.docker.internal` + custom `127.0.0.1` entries from `/etc/hosts` elsewhere                                                                       |

> **`--gcloud` and `--gh` are opt-in once.** The first run with the flag creates and populates the per-project volume. Every later run auto-mounts that volume — no flag needed — until you `claude-docker clean` or `purge`.

### Credential sync (`~/.claude.json`)

Claude Code rewrites this file frequently. Bind-mounting it across the Docker boundary causes inode staleness — host edits stop being visible inside the container, and vice-versa. Instead:

- **Start:** host's `~/.claude.json` → copied into the container
- **Exit:** container's copy → written to `~/.claude/.claude.json.shared` (carried out via the bind-mounted `~/.claude`) → copied back to host's `~/.claude.json`
- **Fallback chain** if host file missing: `~/.claude/.claude.json.shared` → most recent backup under `~/.claude/backups/`

Net effect: same conversation history and credentials inside and outside the container, no manual sync, no stale-inode breakage.

## Commands & flags

**Commands**

| Command                | What it does                                                                                     |
| ---------------------- | ------------------------------------------------------------------------------------------------ |
| `claude-docker`        | Launch (or attach to) Claude Code for the current project                                        |
| `claude-docker shell`  | Open a bash shell inside the running container                                                   |
| `claude-docker status` | Show container info and mounts                                                                   |
| `claude-docker list`   | List all running `claude-docker` containers                                                      |
| `claude-docker stop`   | Stop this project's container                                                                    |
| `claude-docker clean`  | Remove this project's container and volumes (`node_modules`, `gcloud`, `gh`)                     |
| `claude-docker purge`  | **Delete all** `claude-docker` containers and volumes across every project (interactive confirm) |
| `claude-docker update` | Rebuild the Docker image with `--no-cache`                                                       |
| `claude-docker help`   | Show help                                                                                        |

**Flags** (placed before the command)

| Flag            | What it does                                                                                      |
| --------------- | ------------------------------------------------------------------------------------------------- |
| `--gcloud`      | Initialize per-project gcloud auth on first run; auto-mounted thereafter                          |
| `--gh`          | Prompt for a fine-grained GitHub PAT and configure `gh` for this project; auto-mounted thereafter |
| `--resume <id>` | Resume a previous Claude session by ID                                                            |

## Optional integrations

### gcloud (`--gcloud`)

Per-project gcloud auth so projects can't see each other's credentials.

```bash
claude-docker --gcloud        # first run: runs `gcloud auth login --no-launch-browser`
claude-docker                 # subsequent runs: gcloud volume auto-mounted
```

Runs both `gcloud auth login` and `gcloud auth application-default login`. Credentials live in a Docker volume named `claude-docker-gcloud-<project>`. Removed by `claude-docker clean`.

### GitHub (`--gh`)

Per-project GitHub auth via a fine-grained PAT — scoped to whichever repos you select when creating the token, so the container only sees what it needs.

```bash
claude-docker --gh            # prompts for a PAT, runs `gh auth login --with-token`
```

The prompt includes a link to GitHub's token-creation page pre-filled with a sensible description. The token is piped to `gh` and immediately unset from the shell. `gh auth setup-git` is attempted on a best-effort basis (`~/.gitconfig` is read-only inside the container, so configure on the host if needed). Auto-mounted on subsequent runs.

### Resume a session (`--resume`)

```bash
claude-docker --resume <session-id>
```

Forwarded to `claude --resume`. Works both on first run and when attaching to an already-running container.

### Playwright MCP

The Docker image preinstalls `@playwright/mcp` and a matching Chromium browser. Two flags are required for it to work inside Docker; they're harmless on macOS too, so the same config works in both places. Add to `~/.claude.json` under the global `mcpServers` key:

```json
{
  "mcpServers": {
    "playwright": {
      "type": "stdio",
      "command": "npx",
      "args": [
        "@playwright/mcp@latest",
        "--no-sandbox",
        "--ignore-https-errors"
      ],
      "env": {}
    }
  }
}
```

| Flag                    | Why                                            |
| ----------------------- | ---------------------------------------------- |
| `--no-sandbox`          | Chromium sandboxing doesn't work inside Docker |
| `--ignore-https-errors` | Allow self-signed certificates                 |

> **Project-level overrides:** if `~/.claude.json` has a project-level `mcpServers.playwright` entry under your project's path key, it overrides the global one. Add the same flags there or remove the project entry.

## Limitations & caveats

- **macOS and Linux only.** Windows is untested. Apple Silicon and Intel both work.
- **Docker Desktop on macOS loses host networking.** `--network host` is unsupported there, so services on the host must be reached via `host.docker.internal` instead of `localhost`. OrbStack supports host networking and is the smoother choice on macOS.
- **One container per project root.** "Project root" is the nearest ancestor with a lockfile (`pnpm-lock.yaml`, `package-lock.json`, `yarn.lock`, or `pnpm-workspace.yaml`). Working in two subdirectories of the same monorepo shares a container; two different repos get two containers.
- **`node_modules` lives in a Docker volume**, not on the host. Host-side IDE features that rely on `node_modules` (type lookups, ESLint resolution) won't see them. Install on the host too if you need that.
- **`~/.claude.json` is copied, not bind-mounted.** Concurrent edits inside and outside the container during a session can race; the last writer on exit wins. In practice a single host session + a single container session is fine.
- **`~/.gitconfig` and `~/.ssh` are read-only** inside the container. Tools that try to write them (`gh auth setup-git`, `ssh-keygen`) will fail; configure them on the host.
- **gcloud / gh / pnpm-store volumes persist** until `claude-docker clean` (per project) or `claude-docker purge` (all). They are not garbage-collected automatically.
- **Image is ~3–4 GB.** Node LTS + Chromium + gcloud SDK + gh + ffmpeg + uv + hasura CLI. The first `make install` and first `claude-docker` are slow; everything after is fast.
- **Container runs as your host UID with passwordless sudo.** Inside the container, Claude can do anything root can — `apt-get install`, `chmod`, etc. The isolation guarantee is that "anything" stops at the container boundary, not that Claude is unprivileged inside.

## Cleanup

```bash
claude-docker clean              # this project's container + volumes (node_modules, gcloud, gh)
claude-docker purge              # ALL claude-docker containers + volumes across every project (interactive)
docker rmi claude-code-sandbox   # remove the image itself
```

> `purge` also removes the shared pnpm store volume — the next `pnpm install` in any project will refill it from scratch.

## License

MIT
