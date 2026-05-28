# claude-code-dotnet-docker

A self-contained Docker image that runs Claude Code in a .NET 10 dev environment with the Roslyn LSP integration pre-installed. Run from a terminal via `docker run`; not designed as a VS Code Dev Container.

## Quick start

```powershell
# Build
docker build -t claude-code-dotnet-docker .

# Run (PowerShell)
docker run --rm -it `
  -v "C:\path\to\your\project:/workspace" `
  -v claude-config:/home/claude/.claude `
  -v "$env:USERPROFILE\.claude\.credentials.json:/home/claude/.claude/.credentials.json" `
  claude-code-dotnet-docker
```

The container drops you into `/workspace` as user `claude` with `zsh`, `claude` on `PATH`, and the .NET SDK ready.

## What's preinstalled

| Component | Source | Size |
|---|---|---|
| .NET 10 SDK | `mcr.microsoft.com/dotnet/sdk:10.0` base | ~630 MB |
| Claude Code CLI | Native binary from `claude.ai/install.sh` | ~230 MB |
| `roslyn-language-server`, `ClaudeCodeRoslynLspProxy` | `dotnet tool install --global` | ~280 MB |
| Plugin marketplaces (3) | Fetched at build from pinned SHAs | ~7 MB |
| CLI utilities | `gh`, `ripgrep`, `git-delta`, `fzf`, `tree`, `jq`, `nano`, `dnsutils`, `iproute2`, `zsh` + oh-my-zsh + powerlevel10k | — |

## Plugins

Three marketplaces are pre-installed and enabled by default:

- `claude-roslyn-lsp` ← `unsafePtr/ClaudeCodeRoslynLspProxy`
- `dotnet-agent-skills` ← `dotnet/skills` (sparse-checkout: only `.claude-plugin/` + `plugins/`)
- `microsoft-docs-marketplace` ← `microsoftdocs/mcp`

Each lives under `plugins-src/<name>/` as three small pointer files — **no upstream code is vendored in this repo**:

```
plugins-src/<name>/
  .source-repo    # GitHub owner/repo
  .commit-sha     # pinned commit SHA
  .sparse-paths   # optional, space-separated paths for sparse-checkout
```

At build time, `install-plugins.sh` clones each repo at its pinned SHA into a temp dir, then materialises the plugin layout that Claude Code expects under `/usr/local/share/claude-defaults/plugins/`. On first container start, `entrypoint.sh` copies that into the user's `~/.claude/plugins/` (via the named volume).

### Updating a plugin

1. Look up the new SHA on GitHub
2. Overwrite `plugins-src/<name>/.commit-sha`
3. Rebuild — the plugin-installer stage will re-clone at the new SHA

## Security

The container itself is not privileged (no Docker socket, no `--privileged`, no extra capabilities). But the mounts in the quick-start give Claude meaningful host impact:

- `/workspace` is **read/write**. Anything Claude writes there — including a malicious `package.json` `postinstall`, `.git/hooks/post-merge`, or binary with a build step — executes on your host when you next touch the project with host tools.
- `.credentials.json` is **read/write**. Claude can read your OAuth token (exfiltratable via the unrestricted outbound network) or overwrite it.
- The named volume `claude-config` persists arbitrary state across runs (hooks, MCP servers, settings).

Stricter alternatives if it matters:

- Mount workspace read-only: `-v "...:/workspace:ro"`
- Drop the credentials mount and `claude /login` inside the container (needs browser access)
- Add `--cap-drop=ALL --security-opt no-new-privileges`
- Add an egress firewall via `NET_ADMIN` + iptables init script (not done here)

The entrypoint pre-accepts `dangerouslySkipPermissionsAccepted`, so launching with `claude --dangerously-skip-permissions` runs unattended with full workspace RW.

## Gotchas

- **Container "in use" rename issue**: Don't try to rename or delete the build context directory while a Claude Code session is running inside it; Windows holds an exclusive lock on the working directory.
- **Testing first-run behaviour**: The `entrypoint.sh` only seeds plugin defaults into the user's `~/.claude/plugins/` if that directory doesn't already exist. To re-test first-run after upgrading the image, wipe the named volume:
  ```powershell
  docker volume rm claude-config
  ```
- **Credentials chown**: Docker Desktop on Windows/WSL2 exposes bind-mounted files as `root:root 0777`. The entrypoint detects this and `chown`s them to the `claude` user before Claude Code sees them (Claude rejects insecure credential perms).
- **First-run onboarding**: The entrypoint writes `hasCompletedOnboarding: true` into `.claude.json` to skip the theme picker / ToS prompt on every container start.
