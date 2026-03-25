# claude-vm

Run [Claude Code](https://docs.anthropic.com/en/docs/claude-code) inside an isolated local VM — full autonomy, zero risk to your host machine.

## Why

Claude Code works best with `--dangerously-skip-permissions`, but granting that on your real machine is risky. This project solves that by:

- Running Claude inside a dedicated **Multipass VM** (Apple's native hypervisor on macOS)
- **Only mounting the current project** — the VM has no access to the rest of your machine
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
git clone https://github.com/yourname/claude-vm
cd claude-vm
make install

# Go to any project and run
cd ~/my-project
claude-run
```

On first run, `claude-run` will:
1. Create the `claude-sandbox` VM (Ubuntu 22.04, 2 CPUs, 4 GB RAM, 30 GB disk)
2. Bootstrap it with Node.js, Python, Docker, Claude Code, ttyd, Tailscale, and UFW
3. Mount only your current project directory into the VM
4. Launch Claude Code with full permissions inside the sandbox

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

## Remote monitoring

Once Tailscale is authenticated, open from any device on your Tailscale network:

```
http://<tailscale-ip>:7681
```

## How isolation works

| What | Access |
|---|---|
| Current project (`pwd`) | ✅ Mounted read/write |
| Rest of your home folder | ❌ Not visible |
| Other projects | ❌ Not visible |
| `host.docker.internal:<port>` | ✅ Resolved to your Mac |
| Docker inside VM | ✅ Available |

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
