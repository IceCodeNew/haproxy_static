FROM quay.io/icecodenew/builder_image_x86_64-linux:ubuntu AS step1_lua54
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
## curl -sSL "https://www.lua.org/download.html" | tr -d '\r\n\t' | grep -Po '(?<=lua-)[0-9]\.[0-9]\.[0-9](?=\.tar\.gz)' | sort -Vr | head -n 1
ARG lua_version=5.4.3
WORKDIR /build_root
RUN source '/root/.bashrc' \
    && curl -sS "https://www.lua.org/ftp/lua-${lua_version}.tar.gz" | bsdtar --no-xattrs -xf-;
WORKDIR "/build_root/lua-${lua_version}"
RUN sed -i -E 's!MYCFLAGS=.*!MYCFLAGS='"$CFLAGS"' -fPIE -Wl,-pie!' src/Makefile \
    && make all test \
    && checkinstall -y --nodoc --pkgversion="$lua_version"

FROM step1_lua54 AS step3_jemalloc
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# https://api.github.com/repos/jemalloc/jemalloc/releases/latest
ARG jemalloc_latest_tag_name=5.2.1
# https://api.github.com/repos/jemalloc/jemalloc/commits?per_page=1
ARG jemalloc_latest_commit_hash=cdabe908d05ba68da248edf1dd9f522af1ec6024
# WORKDIR /build_root
# RUN source '/root/.bashrc' \
#     && var_icn_download="https://github.com/jemalloc/jemalloc/releases/download/${jemalloc_latest_tag_name}/jemalloc-${jemalloc_latest_tag_name}.tar.bz2" \
#     && curl -sS -- "$var_icn_download" | bsdtar --no-xattrs -xf-;
# WORKDIR "/build_root/jemalloc-${jemalloc_latest_tag_name}"
# RUN ./configure --prefix=/usr --disable-static \
#     && make -j "$(nproc)" CFLAGS="$CFLAGS -fPIC" \
#     && checkinstall -y --nodoc --pkgversion="$jemalloc_latest_tag_name"
WORKDIR '/build_root/jemalloc'
RUN source '/root/.bashrc' \
    && git_clone 'https://github.com/jemalloc/jemalloc.git' '/build_root/jemalloc' \
    && ./autogen.sh --prefix=/usr --disable-static \
    && make -j "$(nproc)" CFLAGS="$CFLAGS -fPIC" \
    && checkinstall -y --nodoc --pkgversion="${jemalloc_latest_tag_name}-dev"

FROM step3_jemalloc AS haproxy_builder
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG haproxy_branch=2.4
## curl -sSL "https://git.haproxy.org/?p=haproxy-${haproxy_branch}.git;a=commit;h=refs/heads/master" | tr -d '\r\n\t' | grep -Po '(?<=<td>commit<\/td><td class="sha1">)[a-zA-Z0-9]+(?=<\/td>)'
ARG haproxy_latest_commit_hash=eba18d5fdd6b04bb8d9a48d0558ed10d9afd1c37
ARG haproxy_latest_tag_name=2.4.8
WORKDIR /build_root
RUN source '/root/.bashrc' \
    && mkdir "haproxy-${haproxy_branch}" \
    && curl -sS "https://git.haproxy.org/?p=haproxy-${haproxy_branch}.git;a=snapshot;h=${haproxy_latest_commit_hash};sf=tgz" | bsdtar --no-xattrs --strip-components 1 -C "haproxy-${haproxy_branch}" -xf-; \
    cd "haproxy-${haproxy_branch}" || exit 1 \
    && make clean \
    && make -j "$(nproc)" TARGET=linux-glibc \
    ADDLIB="-ljemalloc $(jemalloc-config --libs)" \
    USE_LUA=1 LUA_INC=/usr/local/include LUA_LIB=/usr/local/lib LUA_LIB_NAME=lua \
    USE_PCRE2_JIT=1 USE_STATIC_PCRE2=1 USE_SYSTEMD=1 \
    USE_PIE=1 USE_STACKPROTECTOR=1 USE_RELRO_NOW=1 \
    USE_OPENSSL=1 SSL_INC="/build_root/.openssl/include" SSL_LIB="/build_root/.openssl/lib" \
    USE_PROMEX=1 \
    CFLAGS="$CFLAGS -fPIE -pie -fwrapv" \
    && checkinstall -y --nodoc --pkgversion="$haproxy_latest_tag_name" \
    && /usr/local/sbin/haproxy -vvv \
    && sed -E 's/@SBINDIR@/\/usr\/local\/sbin/g' 'admin/systemd/haproxy.service.in' > "/build_root/haproxy-${haproxy_branch}/haproxy.service"

FROM quay.io/icecodenew/alpine:latest AS haproxy-alpine-collection
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
# date +%s
ARG cachebust=1637690108
ARG haproxy_branch=2.4
ARG haproxy_latest_tag_name=2.4.8
ARG jemalloc_latest_tag_name=5.2.1
COPY --from=step3_jemalloc "/build_root/jemalloc/jemalloc_${jemalloc_latest_tag_name}-dev-1_amd64.deb" "/build_root/haproxy-${haproxy_branch}/"
COPY --from=haproxy_builder "/build_root/haproxy-${haproxy_branch}/haproxy_${haproxy_latest_tag_name}-1_amd64.deb" "/build_root/haproxy-${haproxy_branch}/haproxy.service" "/build_root/haproxy-${haproxy_branch}/"
RUN apk update; apk --no-progress --no-cache add \
    bash coreutils curl findutils git; \
    apk --no-progress --no-cache upgrade; \
    rm -rf /var/cache/apk/*
