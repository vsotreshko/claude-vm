# claude-vm

Run [Claude Code](https://docs.anthropic.com/en/docs/claude-code) inside an isolated local VM — full autonomy, zero risk to your host machine.

## Why

Claude Code works best with `--dangerously-skip-permissions`, but granting that on your real machine is risky. This project solves that by:

- Running Claude inside a dedicated **Multipass VM** (Apple's native hypervisor on macOS)
- **Only mounting the current project** — the VM has no access to the rest of your machine
- **Sharing sessions** — project is mounted at the same path as on your Mac, so Claude Code sees your existing conversation history
- **Sharing credentials** — `~/.claude` is mounted into the VM, so you don't need to log in again
- Keeping a **browser-accessible terminal** (ttyd) so you can observe sessions remotely
- Providing **snapshots** so you can roll back if Claude breaks something
- Supporting **Docker** inside the VM for projects that need it
- Resolving `host.docker.internal` so calls to services on your Mac work transparently

## Requirements

- macOS (Apple Silicon or Intel)
- [Homebrew](https://brew.sh)
- A [Tailscale](https://tailscale.com) account (free) — for remote access

## Quick start

```bash
git clone https://github.com/vsotreshko/claude-vm
cd claude-vm
make install

# Go to any project and run
cd ~/my-project
claude-run
```

On first run, `claude-run` will:
1. Install Multipass via Homebrew if not present
2. Create the `claude-sandbox` VM (Ubuntu 22.04, 2 CPUs, 4 GB RAM, 30 GB disk)
3. Bootstrap it with Node.js, Python, Docker, Claude Code, ttyd, Tailscale, and UFW
4. Mount your current project directory and `~/.claude` into the VM
5. Launch Claude Code with `--dangerously-skip-permissions` inside the sandbox

After first bootstrap, authenticate Tailscale once:

```bash
multipass shell claude-sandbox
sudo tailscale up   # follow the URL, then exit
```

## Usage

```bash
claude-run              # launch Claude Code in this repo
claude-run monitor      # open browser terminal to observe remotely
claude-run status       # VM info, active sessions, mounts
claude-run snapshot     # snapshot before risky work
claude-run snapshots    # list all snapshots
claude-run restore <n>  # roll back VM to a snapshot
claude-run stop         # stop the VM
claude-run update       # update Claude Code to latest
```

## Node.js / native binaries

Your Mac's `node_modules` contains macOS-native binaries that won't work inside the Linux VM. `claude-run` automatically detects `node_modules` directories and overlays them with VM-local copies using bind mounts. On first run (or after the overlay is created), run `npm install` (or `pnpm install` / `yarn`) inside the VM to get Linux-native dependencies.

Your Mac's `node_modules` remain untouched — the overlay is stored in the VM at `~/.node_modules_overlay/`.

## Multiple projects

You can run `claude-run` from different project directories in parallel. They share a single VM but get separate mounts and tmux sessions. Avoid running two instances simultaneously on a fresh system (before the VM is created).

## Stopping

```bash
claude-run stop         # unmounts volumes, then gracefully stops (forces after 30s)
```

If stop hangs, force kill:

```bash
multipass stop claude-sandbox --force
```

## Remote monitoring

Once Tailscale is authenticated, open from any device on your Tailscale network:

```
http://<tailscale-ip>:7681
```

## How isolation works

| What | Access |
|---|---|
| Current project (`pwd`) | Mounted read/write at the same absolute path |
| `~/.claude` | Mounted — credentials and session history shared |
| Rest of your home folder | Not visible |
| Other projects | Not visible |
| `localhost:<port>` | Forwarded to your Mac (except SSH, ttyd) |
| `host.docker.internal:<port>` | Resolved to your Mac |
| Docker inside VM | Available |

## Repo structure

```
claude-vm/
├── README.md
├── Makefile
├── .gitignore
├── claude-run          ← install to /usr/local/bin
└── vm-bootstrap.sh     ← runs once inside the VM
```

## Resetting everything

```bash
multipass delete claude-sandbox --purge
# Next claude-run recreates from scratch
```

## License

MIT
