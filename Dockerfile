# ============================================================
# llm-wiki-cli — Docker build
# ============================================================

# --- Build stage ---
FROM debian:bookworm-slim AS builder

WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl bash python3 make g++ pkg-config libssl-dev cargo ca-certificates \
    && rm -rf /var/lib/apt/lists/* && apt-get clean

# Install Bun
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:$PATH"

# Copy source (repo root IS the source, not a subdirectory)
COPY . /app

# Build Rust native tools (PDF extraction, clip server)
# pdfium-binaries feature auto-downloads PDFium
WORKDIR /app/native
RUN sed -i 's/pdfium-render = "0.9"/pdfium-render = { version = "0.9", features = ["pdfium-binaries"] }/' /app/native/Cargo.toml \
    || echo "Cargo.toml already patched"
ENV RUST_LOG=info PDFIUM_BUNDLE=0
RUN cargo build --release 2>&1 | tail -10
RUN cp /app/native/target/release/llm-wiki-native /tmp/llm-wiki-native \
    2>/dev/null || true
RUN PDFIUM_SO=$(find /root/.cargo -name "libpdfium.so" 2>/dev/null | head -1) && \
    cp "$PDFIUM_SO" /tmp/libpdfium.so 2>/dev/null || true

# Build Bun CLI
WORKDIR /app
RUN bun install && bun build --compile cli/index.ts --outfile /tmp/llm-wiki

# --- Production stage ---
FROM debian:bookworm-slim

LABEL maintainer="LLM Wiki CLI"

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash ca-certificates curl wget less ncurses-base tzdata \
    libsqlite3-0 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/* && apt-get clean

RUN groupadd -g 1000 llmwiki && \
    useradd -u 1000 -g llmwiki -h /wiki -s /bin/bash -m llmwiki

WORKDIR /wiki

COPY --from=builder /tmp/llm-wiki /usr/local/bin/llm-wiki
COPY --from=builder /tmp/llm-wiki-native /usr/local/bin/llm-wiki-native
COPY --from=builder /tmp/libpdfium.so /usr/local/lib/libpdfium.so 2>/dev/null || true

RUN chmod +x /usr/local/bin/llm-wiki && \
    chmod +x /usr/local/bin/llm-wiki-native 2>/dev/null || true && \
    ldconfig 2>/dev/null || true

RUN mkdir -p /wiki /root/.llm-wiki-cli && \
    chown llmwiki:llmwiki /wiki /root/.llm-wiki-cli

ENV LLM_WIKI_CONFIG_DIR=/root/.llm-wiki-cli
ENV LLM_WIKI_DATA_DIR=/wiki
ENV TERM=xterm-256color
ENV PDFIUM_DYNAMIC_LIB_PATH=/usr/local/lib/libpdfium.so

EXPOSE 19828 19827

USER llmwiki

HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD wget -qO- http://localhost:19828/api/v1/health 2>/dev/null || exit 1

ENTRYPOINT ["/usr/local/bin/llm-wiki"]
CMD ["--help"]