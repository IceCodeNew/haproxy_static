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
    if $(type -P curl) -LROJq --retry 5 --retry-delay 10 --retry-max-time 60 "$1"; then
      find . -maxdepth 1 -type f -print0 | xargs -0 -i -r -s 2000 sudo "$(type -P install)" -pvD "{}" "$2"
    fi
    popd || exit 1
    /bin/rm -rf "$tmp_dir"
    dirs -c
  fi
}

################

sudo mkdir -p /usr/local/bin
go_collection_tag_name=$(curl -sSL -H "Accept: application/vnd.github.v3+json" \
  'https://api.github.com/repos/IceCodeNew/go-collection/releases/latest' |
  grep 'tag_name' | cut -d\" -f4)

curl_to_dest "https://github.com/IceCodeNew/go-collection/releases/download/${go_collection_tag_name}/github-release" '/usr/local/bin/github-release'

curl_to_dest "https://github.com/IceCodeNew/go-collection/releases/download/${go_collection_tag_name}/got" '/usr/local/bin/got'
