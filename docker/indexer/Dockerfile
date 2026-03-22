FROM rust:1.94.0-bookworm AS builder

ARG PROFILE=release
ARG GIT_REVISION
ENV GIT_REVISION=$GIT_REVISION

WORKDIR /work

COPY Cargo.lock Cargo.toml ./
COPY crates/ ./crates/

RUN apt-get update && apt-get install -y \
    build-essential libssl-dev pkg-config curl cmake clang ca-certificates \
    && rm -rf /var/lib/apt/lists/*

ENV PATH="/root/.cargo/bin:${PATH}"

RUN --mount=type=secret,id=gh_token \
    git config --global url."https://x-access-token:$(cat /run/secrets/gh_token)@github.com/".insteadOf "https://github.com/" && \
    cargo build --profile $PROFILE --bin streams-indexer --config net.git-fetch-with-cli=true

# ── Runtime ─────────────────────────────────────────────────────────────

FROM debian:bookworm-slim AS runtime

RUN apt-get update && apt-get -y --no-install-recommends install \
    ca-certificates libpq-dev curl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /work/target/release/streams-indexer /opt/streams/bin/
COPY entry.sh /entry.sh
RUN chmod +x /opt/streams/bin/streams-indexer /entry.sh

ARG BUILD_DATE
ARG GIT_REVISION
LABEL build-date=$BUILD_DATE
LABEL git-revision=$GIT_REVISION

EXPOSE 9184 8081

CMD ["/entry.sh"]
