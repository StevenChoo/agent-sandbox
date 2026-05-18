FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# ── Base system ───────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    zsh curl git nano unzip zip tar \
    ca-certificates gnupg lsb-release \
    build-essential make pkg-config \
    python3 python3-venv \
    jq yq ripgrep fd-find tree \
    less file \
    netcat-openbsd dnsutils iputils-ping lsof \
    procps \
    openssh-client \
    locales \
    sudo \
    && locale-gen en_US.UTF-8 \
    && update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 LC_CTYPE=en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV LC_CTYPE=en_US.UTF-8

# ── Go ────────────────────────────────────────────────────────────────────────
# uname -m returns x86_64 or aarch64; Go download URLs use amd64 or arm64.
ARG GO_VERSION=1.26.3
RUN ARCH=$(uname -m) && \
    case "${ARCH}" in \
      x86_64)  GO_ARCH="amd64" ;; \
      aarch64) GO_ARCH="arm64" ;; \
      *)       echo "Unsupported arch: ${ARCH}" && exit 1 ;; \
    esac && \
    curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" \
    | tar -C /usr/local -xz
ENV PATH="/usr/local/go/bin:${PATH}"

# ── AWS CLI v2 ────────────────────────────────────────────────────────────────
# AWS CLI download URLs use x86_64 or aarch64, matching uname -m directly.
RUN ARCH=$(uname -m) && \
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${ARCH}.zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/awscliv2.zip /tmp/aws

# ── Agent user ────────────────────────────────────────────────────────────────
ARG AGENT_UID=1000
ARG AGENT_GID=1000
# Ubuntu 24.04 base image ships an 'ubuntu' user at 1000:1000. Remove any
# existing user/group occupying the target UID/GID before creating 'agent'.
RUN if getent passwd "${AGENT_UID}" > /dev/null 2>&1; then \
        userdel -r "$(getent passwd "${AGENT_UID}" | cut -d: -f1)" 2>/dev/null || true; \
    fi; \
    if getent group "${AGENT_GID}" > /dev/null 2>&1; then \
        groupdel "$(getent group "${AGENT_GID}" | cut -d: -f1)"; \
    fi; \
    groupadd -g ${AGENT_GID} agent \
    && useradd -m -u ${AGENT_UID} -g agent -s /bin/zsh agent \
    && echo "agent ALL=(ALL) NOPASSWD: /usr/bin/apt-get" >> /etc/sudoers.d/agent

USER agent
WORKDIR /home/agent

# ── SDKMAN + JDKs ─────────────────────────────────────────────────────────────
ENV SDKMAN_DIR="/home/agent/.sdkman"
RUN curl -s "https://get.sdkman.io" | bash \
    && bash -c "source ${SDKMAN_DIR}/bin/sdkman-init.sh \
        && sdk install java 17.0.11-tem \
        && sdk install java 21.0.3-tem \
        && sdk install java 25.0.3-tem \
        && sdk default java 21.0.3-tem"

# ── Gradle + Maven + byobu (system) ───────────────────────────────────────────
USER root
RUN apt-get update && apt-get install -y --no-install-recommends gradle maven byobu \
    && rm -rf /var/lib/apt/lists/*

# ── Node.js LTS (via nvm) ─────────────────────────────────────────────────────
USER agent
ENV NVM_DIR="/home/agent/.nvm"
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash \
    && bash -c "source ${NVM_DIR}/nvm.sh && nvm install --lts && nvm use --lts && nvm alias default node"

# ── AI agent CLIs ─────────────────────────────────────────────────────────────
RUN bash -c "source ${NVM_DIR}/nvm.sh \
    && npm install -g @anthropic-ai/claude-code \
    && npm install -g @google/gemini-cli"

# ── uv for agent user ─────────────────────────────────────────────────────────
RUN curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/home/agent/.local/bin sh
ENV PATH="/home/agent/.local/bin:${PATH}"

# Pre-generate uv/uvx shell completions so zshrc can source them without the
# startup latency of running `uv generate-shell-completion` on every shell open.
RUN mkdir -p /home/agent/.zsh/completions \
    && /home/agent/.local/bin/uv generate-shell-completion zsh > /home/agent/.zsh/completions/_uv \
    && /home/agent/.local/bin/uvx --generate-shell-completion zsh > /home/agent/.zsh/completions/_uvx

# ── fzf (install script ships the key-bindings/completion files oh-my-zsh needs)
RUN git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf \
    && ~/.fzf/install --no-update-rc --completion --key-bindings

# ── zsh + oh-my-zsh ───────────────────────────────────────────────────────────
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

# ── Shell config ──────────────────────────────────────────────────────────────
COPY --chown=agent:agent config/zshrc /home/agent/.zshrc
COPY --chown=agent:agent config/byobu /home/agent/.byobu
# Pre-seed byobu's status file from the system default so byobu's first-run
# init (which uses cp -n) never races against itself across multiple sessions.
RUN cp /usr/share/byobu/status/status /home/agent/.byobu/status

# ── Volume mount points ───────────────────────────────────────────────────────
# Pre-create all named volume targets as agent so volumes inherit the correct
# ownership on first mount instead of being initialised as root by the runtime.
RUN mkdir -p \
    /home/agent/.gradle \
    /home/agent/.m2 \
    /home/agent/.npm \
    /home/agent/.cache/uv \
    /home/agent/go \
    /home/agent/work

WORKDIR /home/agent/work

CMD ["/bin/zsh"]
