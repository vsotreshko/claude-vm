# claude-run Removal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove all Multipass VM backend code and documentation, leaving the project Docker-only.

**Architecture:** Delete two files (`claude-run`, `vm-bootstrap.sh`), strip Makefile to Docker-only targets, rewrite README removing all VM/Multipass content.

**Tech Stack:** Bash, Makefile, Markdown

---

## File Map

| Action | File | What changes |
|--------|------|--------------|
| Delete | `claude-run` | Entire file removed |
| Delete | `vm-bootstrap.sh` | Entire file removed |
| Modify | `Makefile` | Remove VM targets/steps, docker-only |
| Modify | `README.md` | Remove all Multipass/VM sections |

---

### Task 1: Delete claude-run and vm-bootstrap.sh

**Files:**
- Delete: `claude-run`
- Delete: `vm-bootstrap.sh`

- [ ] **Step 1: Delete the files**

```bash
rm /Users/vsotreshko/Projects/claude-vm/claude-run
rm /Users/vsotreshko/Projects/claude-vm/vm-bootstrap.sh
```

- [ ] **Step 2: Verify they're gone**

```bash
ls /Users/vsotreshko/Projects/claude-vm/
```

Expected output contains: `Dockerfile.claude  Makefile  README.md  claude-docker  settings.claude.example.json`  
Does NOT contain: `claude-run` or `vm-bootstrap.sh`

- [ ] **Step 3: Commit**

```bash
git add -u
git commit -m "feat: remove claude-run and vm-bootstrap.sh"
```

---

### Task 2: Update Makefile

**Files:**
- Modify: `Makefile`

Current file has these targets: `install`, `uninstall`, `update`, `bootstrap-local`, `status`, `help`

- [ ] **Step 1: Replace Makefile with docker-only version**

Replace the entire contents of `Makefile` with:

```makefile
.PHONY: install uninstall update help

INSTALL_DIR   := /usr/local/bin
BOOTSTRAP_DIR := $(HOME)/.claude-vm

install: ## Install claude-docker to /usr/local/bin
	@echo "==> Installing claude-docker to $(INSTALL_DIR)..."
	@chmod +x claude-docker
	@sudo cp claude-docker $(INSTALL_DIR)/claude-docker
	@echo "==> Copying support files to $(BOOTSTRAP_DIR)..."
	@mkdir -p $(BOOTSTRAP_DIR)
	@cp Dockerfile.claude $(BOOTSTRAP_DIR)/Dockerfile.claude
	@echo " ✓  Done. Run 'claude-docker' from any project directory."

uninstall: ## Remove claude-docker from /usr/local/bin
	@sudo rm -f $(INSTALL_DIR)/claude-docker
	@echo " ✓  claude-docker removed."

update: ## Re-install after pulling latest changes
	@$(MAKE) install
	@echo " ✓  claude-docker updated."

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*##' Makefile \
	  | awk 'BEGIN {FS = ":.*##"}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
```

- [ ] **Step 2: Verify**

```bash
make help
```

Expected output lists: `install`, `uninstall`, `update`, `help`. Does NOT list `bootstrap-local` or `status`.

- [ ] **Step 3: Commit**

```bash
git add Makefile
git commit -m "feat: strip Makefile to docker-only targets"
```

---

### Task 3: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Replace README with docker-only version**

Replace the entire contents of `README.md` with:

```markdown
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
```

- [ ] **Step 2: Verify no VM references remain**

```bash
grep -i "multipass\|claude-run\|tailscale\|vm-bootstrap\|Option A\|Option B\|claude-sandbox" /Users/vsotreshko/Projects/claude-vm/README.md
```

Expected: no output (zero matches).

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: rewrite README as docker-only"
```
