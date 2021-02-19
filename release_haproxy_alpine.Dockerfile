# syntax=docker.io/docker/dockerfile-upstream:1.2.0
FROM quay.io/icecodenew/haproxy_static:alpine AS haproxy_uploader
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG haproxy_branch=2.2
ARG haproxy_latest_tag_name=2.2.4
COPY got_github_release.sh /tmp/got_github_release.sh
WORKDIR "/git/haproxy_static"
# import secret:
RUN --mount=type=secret,id=GIT_AUTH_TOKEN,dst=/tmp/secret_token export GITHUB_TOKEN="$(cat /tmp/secret_token)" \
    && bash /tmp/got_github_release.sh \
    && git clone -j "$(nproc)" "https://IceCodeNew:${GITHUB_TOKEN}@github.com/IceCodeNew/haproxy_static.git" "/git/haproxy_static" \
    && git fetch origin --prune --prune-tags \
    && git remote -v; \
    echo '' \
    && echo '$$$$$$$$ github-release $$$$$$$$' \
    && echo '' \
    && set -x; \
    grep -Fq "v${haproxy_latest_tag_name}" <(git tag) \
    && github-release delete \
    --user IceCodeNew \
    --repo haproxy_static \
    --tag "v${haproxy_latest_tag_name}" \
    && git push origin -d "v${haproxy_latest_tag_name}"; \
    < <(echo 'The released deb packages can only work on Ubuntu 20.04, Debian 11, or later OSs. For a more compatible release, see https://github.com/cbdb-project/haproxy_static/releases.' && echo 'It is recommended to initiate a Systemd drop-in file for the haproxy that supports the sdnotify features of systemd, just issue command `mkdir -p "/etc/systemd/system/haproxy.service.d" && echo -e "[Service]\nRestartSec=6" > "/etc/systemd/system/haproxy.service.d/haproxy.conf"`' && echo 'For the haproxy that **DOES NOT** support the sdnotify features of systemd, issue command `mkdir -p "/etc/systemd/system/haproxy.service.d" && echo -e "[Service]\nExecStart=\nExecStart=/usr/local/sbin/haproxy -W -f $CONFIG -p $PIDFILE $EXTRAOPTS\nType=\nType=forking\nRestartSec=6" > "/etc/systemd/system/haproxy.service.d/haproxy.conf"`') \
    github-release release \
    --user IceCodeNew \
    --repo haproxy_static \
    --tag "v${haproxy_latest_tag_name}" \
    --name "v${haproxy_latest_tag_name}" \
    --description - \
    --target release \
    && sleep 3s \
    && github-release upload \
    --user IceCodeNew \
    --repo haproxy_static \
    --tag "v${haproxy_latest_tag_name}" \
    --name "haproxy" \
    --file "/build_root/haproxy-${haproxy_branch}/haproxy"
