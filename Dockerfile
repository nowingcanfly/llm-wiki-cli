# ============================================================
# llm-wiki-cli - Docker build (CLI only)
# ============================================================

# --- Build stage ---
FROM debian:bookworm-slim AS builder

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends     curl bash python3 make g++ pkg-config libssl-dev ca-certificates unzip git     && rm -rf /var/lib/apt/lists/* && apt-get clean

# Install Bun
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:$PATH"

COPY . /app

# Build CLI binary
RUN bun install && bun build --compile cli/index.ts --outfile /tmp/llm-wiki

# --- Production stage ---
FROM debian:bookworm-slim

LABEL maintainer="LLM Wiki CLI"

RUN apt-get update && apt-get install -y --no-install-recommends     bash ca-certificates curl wget less ncurses-base tzdata     libsqlite3-0 libglib2.0-0     && rm -rf /var/lib/apt/lists/* && apt-get clean

# Create user BEFORE creating dirs that reference it
RUN groupadd -g 1000 llmwiki     && useradd -u 1000 -g llmwiki -s /bin/bash -r -M llmwiki

# Create data dirs
RUN mkdir -p /wiki /root/.llm-wiki-cli && chown llmwiki:llmwiki /wiki /root/.llm-wiki-cli

WORKDIR /wiki

COPY --from=builder /tmp/llm-wiki /usr/local/bin/llm-wiki

RUN chmod +x /usr/local/bin/llm-wiki

ENV LLM_WIKI_CONFIG_DIR=/root/.llm-wiki-cli
ENV LLM_WIKI_DATA_DIR=/wiki
ENV TERM=xterm-256color

EXPOSE 19828 19827

USER llmwiki

ENTRYPOINT ["/usr/local/bin/llm-wiki"]
CMD ["--help"]
