# syntax = docker/dockerfile:1.0-experimental
FROM quay.io/icecodenew/haproxy_static:alpine AS haproxy_uploader
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG haproxy_branch='2.2'
ARG haproxy_latest_tag_name='2.2.4'
COPY got_github_release.sh /tmp/got_github_release.sh
WORKDIR "/root/haproxy_static/haproxy-${haproxy_branch}"
# import secret:
RUN --mount=type=secret,id=GIT_AUTH_TOKEN,dst=/tmp/secret_token export GITHUB_TOKEN="$(cat /tmp/secret_token)" \
    && source "/root/.bashrc" \
    && bash /tmp/got_github_release.sh \
    && github-release release \
    --user IceCodeNew \
    --repo haproxy_static \
    --tag "v${haproxy_latest_tag_name}" \
    --name "v${haproxy_latest_tag_name}"; \
    github-release upload \
    --user IceCodeNew \
    --repo haproxy_static \
    --tag "v${haproxy_latest_tag_name}" \
    --name "haproxy" \
    --file "/root/haproxy_static/haproxy-${haproxy_branch}/haproxy"; \
    # github-release upload \
    # --user IceCodeNew \
    # --repo haproxy_static \
    # --tag "v${haproxy_latest_tag_name}" \
    # --name "haproxy.ori" \
    # --file "/root/haproxy_static/haproxy-${haproxy_branch}/haproxy.ori"
