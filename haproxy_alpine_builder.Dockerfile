FROM quay.io/icecodenew/builder_image_x86_64-linux:alpine AS step1_lua54
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
## curl -sSL "https://www.lua.org/download.html" | tr -d '\r\n\t' | grep -Po '(?<=lua-)[0-9]\.[0-9]\.[0-9](?=\.tar\.gz)' | sort -Vr | head -n 1
ARG lua_version=5.4.4
ARG image_build_date=2022-12-09
ARG dockerfile_workdir=/build_root/lua
WORKDIR $dockerfile_workdir
RUN curl -sS "https://www.lua.org/ftp/lua-${lua_version}.tar.gz" | bsdtar -xf- --strip-components 1 --no-xattrs \
    && sed -i -E 's!MYCFLAGS=.*!MYCFLAGS='"$CFLAGS"' -fPIE -Wl,-pie!' src/Makefile \
    && mold -run make all test \
    && make install \
    && rm -rf -- "$dockerfile_workdir"

FROM step1_lua54 AS haproxy_builder
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG haproxy_branch=2.4
## curl -sSL "https://git.haproxy.org/?p=haproxy-${haproxy_branch}.git;a=commit;h=refs/heads/master" | tr -d '\r\n\t' | grep -Po '(?<=<td>commit<\/td><td class="sha1">)[a-zA-Z0-9]+(?=<\/td>)'
ARG haproxy_latest_commit_hash=6609cbe87cdd3d9c2ad69fa3447ddaf1785abd11
ARG dockerfile_workdir=/build_root/haproxy
WORKDIR $dockerfile_workdir
RUN curl -fsSL "https://git.haproxy.org/?p=haproxy-${haproxy_branch}.git;a=snapshot;h=${haproxy_latest_commit_hash};sf=tgz" | bsdtar -xf- --strip-components 1 --no-xattrs \
    && CFLAGS="$CFLAGS -fPIE -fwrapv" \
    && CXXFLAGS="$CXXFLAGS -fPIE -fwrapv" \
    && LDFLAGS="$LDFLAGS -static-pie -nolibc -Wl,-Bstatic -L /usr/lib -l:libc.a" \
    && export CFLAGS CXXFLAGS LDFLAGS \
    && make clean \
    && mold -run make -j "$(nproc)" TARGET=linux-musl \
    USE_LUA=1 LUA_INC=/usr/local/include LUA_LIB=/usr/local/lib LUA_LIB_NAME=lua \
    USE_PCRE2_JIT=1 USE_STATIC_PCRE2=1 \
    USE_PIE=1 USE_STACKPROTECTOR=1 USE_RELRO_NOW=1 \
    USE_OPENSSL=1 SSL_INC="/usr/include/openssl" SSL_LIB="/usr/lib" \
    USE_PROMEX=1 \
    && strip -o /haproxy ./haproxy \
    && readelf -p .comment /haproxy \
    && rm -rf -- "$dockerfile_workdir"

FROM quay.io/icecodenew/alpine:latest AS haproxy-alpine-collection
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
COPY --from=haproxy_builder "/haproxy" /
RUN apk update; apk --no-progress --no-cache add \
    bash coreutils curl findutils git; \
    apk --no-progress --no-cache upgrade; \
    rm -rf /var/cache/apk/*
