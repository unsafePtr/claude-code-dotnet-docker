# Stage 1: Download Claude Code binary AND build the plugin layout.
# Both use the same ubuntu base and share ca-certificates; combining avoids
# duplicate apt-get update layers. Plugin sources are fetched from GitHub at
# SHAs pinned in plugins-src/<name>/.commit-sha (no vendoring in build context).
FROM ubuntu:noble AS claude-and-plugins
RUN apt-get update && apt-get install -y --no-install-recommends \
  ca-certificates curl git jq && \
  rm -rf /var/lib/apt/lists/*
# Pinned Claude Code version. Bumped automatically by the
# check-claude-update workflow (.github/workflows/check-claude-update.yml),
# which opens a PR whenever downloads.claude.ai/.../latest moves ahead of this.
ARG CLAUDE_CODE_VERSION=2.1.159
RUN base="https://downloads.claude.ai/claude-code-releases" && \
  case "$(dpkg --print-architecture)" in \
    amd64) platform="linux-x64" ;; \
    arm64) platform="linux-arm64" ;; \
    *) echo "unsupported architecture: $(dpkg --print-architecture)" >&2; exit 1 ;; \
  esac && \
  curl -fsSL "${base}/${CLAUDE_CODE_VERSION}/manifest.json" -o /tmp/manifest.json && \
  checksum="$(jq -r ".platforms[\"${platform}\"].checksum" /tmp/manifest.json)" && \
  curl -fsSL "${base}/${CLAUDE_CODE_VERSION}/${platform}/claude" -o /claude-binary && \
  echo "${checksum}  /claude-binary" | sha256sum -c - && \
  chmod +x /claude-binary && rm /tmp/manifest.json
COPY plugins-src /plugins-src
COPY install-plugins.sh /tmp/install-plugins.sh
RUN chmod +x /tmp/install-plugins.sh && /tmp/install-plugins.sh

# Stage 2: Final image
FROM mcr.microsoft.com/dotnet/sdk:10.0

ARG TZ=UTC
ENV TZ="$TZ"

# Install CLI utilities in a single layer. (PowerShell is already in the
# .NET SDK base image — no need to apt-install it.)
ARG GIT_DELTA_VERSION=0.18.2
RUN rm -f /etc/dpkg/dpkg.cfg.d/excludes && \
  apt-get update && apt-get install -y --no-install-recommends \
  less \
  sudo \
  fzf \
  zsh \
  gh \
  jq \
  nano \
  tree \
  ripgrep \
  procps \
  iproute2 \
  dnsutils \
  && ARCH=$(dpkg --print-architecture) \
  && wget "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" \
  && dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" \
  && rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

ENV DOTNET_CLI_TELEMETRY_OPTOUT=1
ENV DOTNET_NOLOGO=1

# Copy Claude Code binary and pre-installed plugins from the builder stage
COPY --from=claude-and-plugins /claude-binary /usr/local/bin/claude
COPY --from=claude-and-plugins /usr/local/share/claude-defaults/plugins /usr/local/share/claude-defaults/plugins

# Reconfigure existing ubuntu user as claude
ARG USERNAME=claude
RUN usermod -l $USERNAME -d /home/$USERNAME -m ubuntu && \
  groupmod -n $USERNAME ubuntu && \
  chsh -s /bin/zsh $USERNAME && \
  echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME && \
  chmod 0440 /etc/sudoers.d/$USERNAME

# Persist bash history across container restarts
RUN mkdir /commandhistory && \
  touch /commandhistory/.bash_history && \
  chown -R $USERNAME /commandhistory

# Keep all Claude Code state (.claude.json, .credentials.json, projects/, sessions/)
# inside /home/claude/.claude so a single named-volume mount preserves everything.
# Without this, .claude.json lives at /home/claude/.claude.json (outside the volume)
# and is wiped by `docker run --rm`, forcing onboarding every run.
ENV CLAUDE_CONFIG_DIR=/home/claude/.claude

# Create workspace and config directories
RUN mkdir -p /workspace /home/$USERNAME/.claude && \
  chown -R $USERNAME:$USERNAME /workspace /home/$USERNAME/.claude

WORKDIR /workspace

# Switch to non-root user
USER $USERNAME

ENV SHELL=/bin/zsh
ENV EDITOR=nano
ENV VISUAL=nano
ENV PATH="/home/claude/.local/bin:/home/claude/.dotnet/tools:$PATH"

# Pre-install dotnet global tools required by the roslyn-lsp plugin
# (per ClaudeCodeRoslynLspProxy README: both tools must be on PATH)
RUN dotnet tool install --global roslyn-language-server --prerelease && \
  dotnet tool install --global ClaudeCodeRoslynLspProxy

# Install zsh with powerlevel10k theme
ARG ZSH_IN_DOCKER_VERSION=1.2.0
RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
  -p git \
  -p fzf \
  -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \
  -a "source /usr/share/doc/fzf/examples/completion.zsh" \
  -a "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  -x

# Copy default Claude config and entrypoint
COPY CLAUDE.md /usr/local/share/claude-defaults/CLAUDE.md
COPY settings.json /usr/local/share/claude-defaults/settings.json
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["zsh"]
