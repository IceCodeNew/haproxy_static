#!/bin/bash

# IMPORTANT!
# `apt` does not have a stable CLI interface. Use with caution in scripts.
## Refer: https://askubuntu.com/a/990838
export DEBIAN_FRONTEND=noninteractive

## Refer: https://unix.stackexchange.com/a/356759
export PAGER='cat'
export SYSTEMD_PAGER=cat

curl() {
  $(type -P curl) -LRq --retry 5 --retry-delay 10 --retry-max-time 60 "$@"
}
curl_to_dest() {
  if [[ $# -eq 2 ]]; then
    tmp_dir=$(mktemp -d)
    pushd "$tmp_dir" || exit 1
    if curl -OJ "$1"; then
      find . -maxdepth 1 -type f -print0 | xargs -0 -i -r -s 2000 "$(type -P install)" -pvD "{}" "$2"
    fi
    popd || exit 1
    /bin/rm -rf "$tmp_dir"
    dirs -c
  fi
}

################

mkdir -p /usr/local/bin

curl_to_dest "https://cdn.jsdelivr.net/gh/IceCodeNew/go-collection@latest-release/assets/github-release" '/usr/local/bin/github-release'
