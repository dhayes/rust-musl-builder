# syntax=docker/dockerfile:1.7-labs
#
# Modern rust-musl-builder style image:
# - Ubuntu 24.04 base
# - rustup toolchain (ARG TOOLCHAIN) with x86_64-unknown-linux-musl target
# - sccache enabled (RUSTC_WRAPPER) for fast incremental rebuilds
# - cargo/rustup/sccache caches exposed as volumes
# - non-root "rust" user with sudo (optional)
#
# Build:
#   docker build -t ghcr.io/yourorg/rust-musl-builder:1.84-musl-sccache .
#
# Use in your project Dockerfile:
#   FROM ghcr.io/yourorg/rust-musl-builder:1.84-musl-sccache as builder
#   # see notes below for multi-stage usage

FROM ubuntu:24.04

ARG TOOLCHAIN=stable

ENV DEBIAN_FRONTEND=noninteractive

# --- Base system deps (no legacy 18.04 pinning) ---
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      build-essential \
      cmake \
      curl \
      file \
      git \
      ca-certificates \
      pkg-config \
      graphviz \
      unzip \
      # MUSL toolchain
      musl \
      musl-dev \
      musl-tools \
      # Optional DB headers for linking (remove if not needed)
      libpq-dev \
      libsqlite3-dev \
      # Optional OpenSSL headers for linking (remove if you vendor)
      libssl-dev \
      # misc
      xutils-dev \
      sudo && \
    rm -rf /var/lib/apt/lists/*

# --- Create non-root user (uid/gid 1000) with sudo (optional) ---
RUN useradd rust --user-group --create-home --shell /bin/bash --groups sudo && \
    echo "rust ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/010-rust && chmod 0440 /etc/sudoers.d/010-rust

# --- Rust via rustup (root install into /opt/rust) ---
ENV RUSTUP_HOME=/opt/rust/rustup \
    CARGO_HOME=/opt/rust/cargo \
    PATH=/opt/rust/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN curl https://sh.rustup.rs -sSf | \
    sh -s -- -y --default-toolchain ${TOOLCHAIN} --profile minimal --no-modify-path && \
    rustup component add rustfmt clippy && \
    rustup target add x86_64-unknown-linux-musl

# --- sccache for faster rebuilds ---
RUN cargo install sccache
ENV RUSTC_WRAPPER=/opt/rust/cargo/bin/sccache \
    SCCACHE_DIR=/opt/rust/sccache

# --- Default cargo config: build for MUSL unless overridden ---
RUN mkdir -p /opt/rust/cargo/.cargo && \
    printf '[build]\ntarget = "x86_64-unknown-linux-musl"\n' > /opt/rust/cargo/.cargo/config.toml

# --- Convenience symlink so the rust user sees the same config ---
USER rust
RUN mkdir -p /home/rust/.cargo && \
    ln -s /opt/rust/cargo/.cargo/config.toml /home/rust/.cargo/config.toml || true

# --- Expose caches as volumes so CI/local can persist them across runs ---
# (You can also mount them explicitly with BuildKit cache mounts in your project Dockerfile.)
VOLUME ["/opt/rust/cargo/registry", "/opt/rust/cargo/git", "/opt/rust/sccache", "/opt/rust/rustup"]

WORKDIR /home/rust/src

# Print tool versions by default (handy in CI)
CMD bash -lc 'echo "Toolchain:" && rustc -V && cargo -V && sccache --version && echo "Target(s):" && rustup target list --installed && echo "Ready."'

