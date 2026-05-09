# Per-Container gcloud Auth

**Date:** 2026-05-09

## Problem

`~/.config/gcloud` is currently mounted from the host into every container. This leaks the same Google account into all containers — no isolation, no per-project accounts.

## Goal

- No gcloud by default
- Opt-in via `--gcloud` flag on first run → interactive login
- Credentials persist across restarts via named Docker volume
- To switch accounts: `claude-docker clean` + restart with `--gcloud`

## Design

### Flag

`--gcloud-login` → `--gcloud`

The old name implied login runs every time. New name means "I want gcloud in this container."

### Volume

Named volume: `claude-docker-gcloud-<project-name>`  
Mounted at: `/home/claude/.config/gcloud`

Docker creates the volume implicitly on first `docker run`. No explicit `docker volume create` needed.

### Mount logic (cmd_run)

Remove host mount:

```bash
# REMOVED:
[ -d "$HOME/.config/gcloud" ] && vol_flags+=(-v "$HOME/.config/gcloud:/home/claude/.config/gcloud")
```

Replace with:

```bash
if [ "$USE_GCLOUD" = true ] || docker volume inspect "$GCLOUD_VOL_NAME" &>/dev/null 2>&1; then
  vol_flags+=(-v "${GCLOUD_VOL_NAME}:/home/claude/.config/gcloud")
fi
```

This covers both cases:

- First run with `--gcloud`: volume created, login runs
- Subsequent restarts (no flag): volume detected → mounted silently, no login

### Login (startup command)

Only runs when `--gcloud` flag is explicitly passed:

```bash
if [ "$USE_GCLOUD" = true ]; then
  startup_cmd="${startup_cmd}gcloud auth login --no-launch-browser && gcloud auth application-default login --no-launch-browser; "
fi
```

### Cleanup (cmd_clean)

Add to existing clean sequence:

```bash
log "Removing gcloud volume '$GCLOUD_VOL_NAME'..."
docker volume rm "$GCLOUD_VOL_NAME" 2>/dev/null && success "gcloud volume removed" || warn "gcloud volume not found"
```

### Variables

```bash
GCLOUD_VOL_NAME="claude-docker-gcloud-${PROJECT_NAME}"
USE_GCLOUD=false  # set to true when --gcloud flag passed
```

## User flow

| Scenario                                    | Behavior                                                                                            |
| ------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| First run, no flag                          | No gcloud in container                                                                              |
| First run, `--gcloud`                       | Volume created, interactive login runs                                                              |
| Restart, no flag                            | Volume detected → mounted, no login                                                                 |
| Restart, `--gcloud`                         | Volume mounted, login runs again                                                                    |
| Attach to running container with `--gcloud` | Flag ignored — mounts are fixed at `docker run` time; gcloud already mounted if set up on first run |
| `clean`                                     | Container + node_modules + gcloud volume all removed                                                |
| Switch account                              | `claude-docker clean` → `claude-docker --gcloud`                                                    |

## Files changed

- `claude-docker`: flag rename, variable rename, mount logic, startup cmd, clean cmd, usage text
