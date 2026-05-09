# Per-Container GitHub (`gh`) Auth

**Date:** 2026-05-09

## Problem

Claude Code in the container currently has no `gh` CLI available, and there is no mechanism to give it GitHub access scoped to specific repos. Without scoping, any credential would grant access to the user's entire GitHub account — risking unintended changes to repos outside the current project.

## Goal

- No `gh` access by default
- Opt-in via `--gh` flag on first run → interactive fine-grained PAT setup
- Access restricted to repos the user explicitly selects when creating the PAT
- Credentials persist across restarts via named Docker volume
- To revoke or change: `claude-docker clean` + restart with `--gh`

## Design

### Flag

`--gh` — mirrors the `--gcloud` flag pattern.

### Volume

Named volume: `claude-docker-gh-<project-name>`
Mounted at: `/home/claude/.config/gh`

Docker creates the volume implicitly on first `docker run`. No explicit `docker volume create` needed.

### Variables

```bash
USE_GH=false
GH_VOL_NAME="claude-docker-gh-${PROJECT_NAME}"
```

### Flag parsing

```bash
--gh) USE_GH=true; shift ;;
```

### Mount logic (cmd_run)

Mount if flag set OR volume already exists (covers silent re-attach on restart):

```bash
if [ "$USE_GH" = true ] || docker volume inspect "$GH_VOL_NAME" &>/dev/null; then
  vol_flags+=(-v "${GH_VOL_NAME}:/home/claude/.config/gh")
fi
```

### Auth flow (startup command)

Only runs when `--gh` flag is explicitly passed. Prints a pre-filled PAT creation URL, prompts for the token, then calls `gh auth login --with-token`:

```bash
if [ "$USE_GH" = true ]; then
  startup_cmd="${startup_cmd}sudo chown -R claude:claude /home/claude/.config/gh; "
  startup_cmd="${startup_cmd}echo '' && echo '==> GitHub auth — create a fine-grained PAT:' && echo '    https://github.com/settings/personal-access-tokens/new?description=claude-docker-${PROJECT_NAME}' && echo '    Select repos to allow, set permissions, then paste the token:' && printf 'Token: ' && read -r _GH_TOKEN && echo \"\$_GH_TOKEN\" | gh auth login --with-token; "
fi
```

The `?description=` param pre-fills the token name on GitHub's creation page.

The `chown` is required because Docker creates named volumes as root.

### Cleanup (cmd_clean)

```bash
log "Removing gh volume '$GH_VOL_NAME'..."
docker volume rm "$GH_VOL_NAME" 2>/dev/null && success "gh volume removed" || warn "gh volume not found"
```

### Usage text

Add to Flags section:

```
    --gh                Fine-grained GitHub PAT auth (scoped to selected repos, persists until clean)
```

### Dockerfile

Install `gh` via official GitHub apt repo, before `USER claude`:

```dockerfile
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*
```

## User flow

| Scenario             | Behavior                                                          |
| -------------------- | ----------------------------------------------------------------- |
| First run, no flag   | No `gh` in container                                              |
| First run, `--gh`    | Volume created, URL printed, token prompted, `gh auth login` runs |
| Restart, no flag     | Volume detected → mounted silently, no prompt                     |
| Restart, `--gh`      | Volume mounted, auth runs again (re-token if needed)              |
| `clean`              | gh volume removed along with container and node_modules volume    |
| Switch repos/account | `claude-docker clean` → `claude-docker --gh`                      |

## Files changed

- `Dockerfile.claude`: add `gh` installation
- `claude-docker`: new `USE_GH`/`GH_VOL_NAME` vars, `--gh` flag, mount logic, startup auth cmd, clean cmd, usage text
