#!/bin/bash

get_latest_version() {
  curl -s "$1$2" |
    grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' |
      sort -V | tail -n 1
}

export BASH_URL='https://ftp.gnu.org/gnu/bash'
export BASH_VERSION="$(get_latest_version "$BASH_URL" '/')"
export BASH_PATCH_LEVEL="${BASH_VERSION##*.}"

export MUSL_URL='https://musl.libc.org/releases'
export MUSL_VERSION="$(get_latest_version "$BASH_URL" '.html')"