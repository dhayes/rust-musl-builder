# syntax=docker/dockerfile:1.7-labs
FROM ubuntu:24.04

ARG TOOLCHAIN=stable
ENV DEBIAN_FRONTEND=noninteractive

# System deps (drop libpq-dev/libsqlite3-dev/libssl-dev if not needed)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake curl file git ca-certificates pkg-config unzip \
    musl musl-dev musl-tools \
    libssl-dev libpq-dev libsqlite3-dev sudo \
 && rm -rf /var/lib/apt/lists/*

# Non-root user
RUN useradd rust --user-group --create-home --shell /bin/bash && \
    echo "rust ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/010-rust && chmod 0440 /etc/sudoers.d/010-rust
USER rust
WORKDIR /home/rust

# Per-user tool dirs
ENV CARGO_HOME=/home/rust/.cargo \
    RUSTUP_HOME=/home/rust/.rustup \
    PATH=/home/rust/.cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Install rustup toolchain + MUSL target
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain ${TOOLCHAIN} --profile minimal --no-modify-path && \
    rustup component add rustfmt clippy && \
    rustup target add x86_64-unknown-linux-musl

# Install sccache (do NOT set RUSTC_WRAPPER yet)
# If you prefer pinning: add `--locked --version <x.y.z>`
RUN cargo install sccache

# Now enable sccache
ENV SCCACHE_DIR=/home/rust/.cache/sccache \
    RUSTC_WRAPPER=/home/rust/.cargo/bin/sccache

# Default Cargo config: target MUSL unless overridden
RUN mkdir -p /home/rust/.cargo && \
    printf '[build]\ntarget = "x86_64-unknown-linux-musl"\n' > /home/rust/.cargo/config.toml

# Optional: expose caches as volumes
VOLUME ["/home/rust/.cargo/registry", "/home/rust/.cargo/git", "/home/rust/.cache/sccache", "/home/rust/.rustup"]

WORKDIR /home/rust/src
CMD bash -lc 'rustc -V && cargo -V && sccache --version && rustup target list --installed && echo "Ready (musl target preinstalled)."'

