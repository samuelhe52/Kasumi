#!/bin/sh
set -eu

cd "$(dirname "$0")/../../.."

if ! command -v rustup >/dev/null 2>&1; then
    brew install rustup
    export PATH="$(brew --prefix rustup)/bin:$PATH"
fi

# Install the toolchain and targets declared in rust-toolchain.toml.
rustup toolchain install --no-update --no-self-update
export PATH="$(dirname "$(rustup which cargo)"):$PATH"
make native
