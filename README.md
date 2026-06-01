# claude-code-dotnet-docker

A self-contained Docker image that runs Claude Code in a .NET 10 dev environment with the Roslyn LSP integration pre-installed. Run from a terminal via `docker run`; not designed as a VS Code Dev Container.

## Quick start

Pre-built images are published to Docker Hub and GHCR:

- `docker.io/unsafeptr/claude-code-dotnet-docker:latest`
- `ghcr.io/unsafeptr/claude-code-dotnet-docker:latest`

`:latest` always tracks the newest build; see [Versioning](#versioning) for pinnable tags.

Pull and run — no clone or build required:

```powershell
docker run --rm -it `
  -v "C:\path\to\your\project:/workspace" `
  -v claude-config:/home/claude/.claude `
  -v "$env:USERPROFILE\.claude\.credentials.json:/home/claude/.claude/.credentials.json" `
  unsafeptr/claude-code-dotnet-docker `
  claude --dangerously-skip-permissions
```

The container launches Claude Code directly inside `/workspace` as user `claude`, with the .NET SDK and Roslyn LSP integration ready. The entrypoint pre-accepts the permission prompt, so `--dangerously-skip-permissions` runs unattended with full workspace RW.

Drop the trailing `claude --dangerously-skip-permissions` to get a `zsh` shell instead.

### Build locally (optional)

```powershell
docker build -t claude-code-dotnet-docker .
```

## What's preinstalled

| Component | Source | Size |
|---|---|---|
| .NET 10 SDK | `mcr.microsoft.com/dotnet/sdk:10.0` base | ~630 MB |
| Claude Code CLI | Pinned native binary, SHA-256 verified at build | ~240 MB |
| `roslyn-language-server`, `ClaudeCodeRoslynLspProxy` | `dotnet tool install --global` | ~280 MB |
| Plugin marketplaces (3) | Fetched at build from pinned SHAs | ~7 MB |
| CLI utilities | `gh`, `ripgrep`, `git-delta`, `fzf`, `tree`, `jq`, `nano`, `dnsutils`, `iproute2`, `zsh` + oh-my-zsh + powerlevel10k | — |

## Versioning

- `:latest` — newest build, updated automatically (see below).
- `:<version>` (e.g. `:2.1.159`, `:2.1`) — immutable, pinnable tags.

The version line started on the repo's own semver (`0.2.0`) and from there tracks the bundled **Claude Code version**: each new Claude Code release is published as an image tagged with that version and `:latest` is moved to it. Pin a specific tag if you need a stable Claude Code release.

## Staying up to date

The image keeps itself current with no manual work:

- **Claude Code** — a daily workflow checks `downloads.claude.ai` for a new release; when one appears it builds, smoke-tests, and publishes the image, then commits the version bump. No-ops when already current.
- **Plugins & tools** — a weekly [Renovate](https://docs.renovatebot.com/) run opens a single PR bumping the pinned plugin SHAs, `git-delta`, `zsh-in-docker`, and GitHub Actions. Merging it ships on the next build.
- **Pre-publish smoke test** — every build runs the image and verifies `claude --version` and `dotnet --version` before pushing, so a broken image is never published.
- **Manual release** — push a `v*` tag on `main` to build and publish on demand (the image tag is the git tag; the Claude version comes from the Dockerfile).

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

Renovate bumps these automatically in its weekly PR. To do it by hand:

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
