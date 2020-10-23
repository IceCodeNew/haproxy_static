FROM quay.io/icecodenew/haproxy_static:debian AS haproxy_uploader
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV haproxy_version="2.2.4"
ARG GITHUB_TOKEN
COPY got_github_release.sh /tmp/got_github_release.sh
RUN source "/root/.bashrc" \
    && bash /tmp/got_github_release.sh
WORKDIR "/root/haproxy_static/haproxy-${haproxy_version}"
RUN github-release release \
    --user IceCodeNew \
    --repo haproxy_static \
    --tag "v${haproxy_version}" \
    --name "v${haproxy_version}"; \
    github-release upload \
    --user IceCodeNew \
    --repo haproxy_static \
    --tag "v${haproxy_version}" \
    --name "haproxy_${haproxy_version}-1_amd64.deb" \
    --file "/root/haproxy_static/haproxy-${haproxy_version}/haproxy_${haproxy_version}-1_amd64.deb"
