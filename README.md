# claude-vm

Run [Claude Code](https://docs.anthropic.com/en/docs/claude-code) inside an isolated Docker container — full autonomy, zero risk to your host machine.

## Why

Claude Code works best with `--dangerously-skip-permissions`, but granting that on your real machine is risky. This project solves that by:

- Running Claude inside a dedicated **Docker container**
- **Only mounting the current project** — the container has no access to the rest of your machine
- **Sharing sessions** — project is mounted at the same path as on your Mac, so Claude Code sees your existing conversation history
- **Sharing credentials** — `~/.claude` and `~/.claude.json` are mounted, so you don't need to log in again
- Optional **gcloud**, **git**, and **SSH** config passthrough

## Requirements

- macOS (Apple Silicon or Intel)
- [Docker Desktop](https://docs.docker.com/get-docker/) (or OrbStack)

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

1. Build the Docker image (Node LTS + git, tmux, gcloud, Claude Code)
2. Create a container with your project directory and `~/.claude` mounted
3. Install npm/pnpm/yarn dependencies if needed
4. Launch Claude Code with `--dangerously-skip-permissions`

## Usage

```bash
claude-docker                    # launch Claude Code in this repo
claude-docker shell              # open a bash shell in the container
claude-docker status             # container info and mounts
claude-docker list               # list all running claude-docker containers
claude-docker stop               # stop the container
claude-docker clean              # remove container and node_modules volume
claude-docker update             # rebuild the Docker image (no cache)
claude-docker help               # show help
```

**Flags:**

```bash
claude-docker --gcloud-login     # run gcloud auth login before starting Claude
```

Running `claude-docker` a second time in the same directory attaches to the existing container and starts a new Claude session.

Running from different directories creates separate containers (one per project).

## How isolation works

| What                           | Access                                           |
| ------------------------------ | ------------------------------------------------ |
| Current project (`pwd`)        | Mounted read/write at the same absolute path     |
| `~/.claude` + `~/.claude.json` | Mounted — credentials and session history shared |
| `~/.gitconfig`                 | Mounted read-only (if exists)                    |
| `~/.ssh`                       | Mounted read-only (if exists)                    |
| `~/.config/gcloud`             | Mounted (if exists)                              |
| `node_modules`                 | Docker volume overlay (if package.json exists)   |
| Rest of your home folder       | Not visible                                      |
| `/etc/hosts` entries           | Forwarded via `--add-host host-gateway`          |

## Node.js / native binaries

Uses a named Docker volume for `node_modules`, so Linux-native binaries work correctly. Dependencies are installed automatically on first run.

## Repo structure

```
claude-vm/
├── README.md
├── Makefile
├── .gitignore
├── claude-docker           ← Docker container backend
└── Dockerfile.claude       ← Docker image definition
```

## Playwright MCP configuration

The Playwright MCP server needs a couple of flags to work inside Docker. This config also works on macOS (the flags are harmless outside containers). Add to your `~/.claude.json` under the global `mcpServers` key:

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

| Flag                    | Why                                                              |
| ----------------------- | ---------------------------------------------------------------- |
| `--no-sandbox`          | Chromium sandboxing doesn't work inside Docker                   |
| `--ignore-https-errors` | Allows navigating to sites with self-signed certificates         |

The Docker image pre-installs `@playwright/mcp` globally with a matching Chromium browser, so no `--executable-path` is needed.

> **Note:** If you also have a **project-level** Playwright MCP config (under a project path key in `~/.claude.json`), it will override the global one. Either remove the project-level entry or add the same flags there.

## Cleanup

```bash
claude-docker clean              # remove container + volume for current project
docker rmi claude-code-sandbox   # remove the image entirely
```

## License

MIT
