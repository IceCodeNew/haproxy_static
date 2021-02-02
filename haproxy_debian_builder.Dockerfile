FROM quay.io/icecodenew/builder_image_x86_64-linux:ubuntu AS step1_lua54
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
## curl -sSL "https://www.lua.org/download.html" | tr -d '\r\n\t' | grep -Po '(?<=lua-)[0-9]\.[0-9]\.[0-9](?=\.tar\.gz)' | sort -ru | head -n 1
ARG lua_version=5.4.0
WORKDIR /build_root
RUN source '/root/.bashrc' \
    && curl -sS "https://www.lua.org/ftp/lua-${lua_version}.tar.gz" | bsdtar --no-xattrs -xf-;
WORKDIR "/build_root/lua-${lua_version}"
RUN sed -i -E 's!MYCFLAGS=.*!MYCFLAGS='"$CFLAGS"' -fPIE -Wl,-pie!' src/Makefile \
    && make all test \
    && checkinstall -y --nodoc --pkgversion="$lua_version"

FROM step1_lua54 AS step2_libslz
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
## curl -sSL "http://git.1wt.eu/web?p=libslz.git;a=commit;h=refs/heads/master" | tr -d '\r\n\t' | grep -Po '(?<=<td>commit<\/td><td class="sha1">)[a-zA-Z0-9]+(?=<\/td>)'
ARG libslz_latest_commit_hash='ff537154e7f5f2fffdbef1cd8c52b564c1b00067'
WORKDIR /build_root
RUN source '/root/.bashrc' \
    && curl -sS "http://git.1wt.eu/web?p=libslz.git;a=snapshot;h=${libslz_latest_commit_hash};sf=tbz2" | bsdtar --no-xattrs -xf-;
WORKDIR /build_root/libslz
RUN sed -i -E 's!PREFIX     := \/usr\/local!PREFIX     := /usr!' Makefile \
    && make CFLAGS="$CFLAGS -fPIE -Wl,-pie" static

FROM step2_libslz AS step3_jemalloc
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# https://api.github.com/repos/jemalloc/jemalloc/releases/latest
ARG jemalloc_latest_tag_name=5.2.1
# https://api.github.com/repos/jemalloc/jemalloc/commits?per_page=1
ARG jemalloc_latest_commit_hash='f6699803e2772de2a4eb253d5b55f00c3842a950'
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
ARG haproxy_branch=2.2
## curl -sSL "https://git.haproxy.org/?p=haproxy-${haproxy_branch}.git;a=commit;h=refs/heads/master" | tr -d '\r\n\t' | grep -Po '(?<=<td>commit<\/td><td class="sha1">)[a-zA-Z0-9]+(?=<\/td>)'
ARG haproxy_latest_commit_hash=aa3c7001cb32cd9c5bb7b5258459bb971e956438
ARG haproxy_latest_tag_name=2.2.4
WORKDIR /build_root
RUN source '/root/.bashrc' \
    && mkdir "haproxy-${haproxy_branch}" \
    && curl -sS "https://git.haproxy.org/?p=haproxy-${haproxy_branch}.git;a=snapshot;h=${haproxy_latest_commit_hash};sf=tgz" | bsdtar --no-xattrs --strip-components 1 -C "haproxy-${haproxy_branch}" -xf-; \
    cd "haproxy-${haproxy_branch}" || exit 1 \
    && make clean \
    && make -j "$(nproc)" TARGET=linux-glibc EXTRA_OBJS="contrib/prometheus-exporter/service-prometheus.o" \
    ADDLIB="-ljemalloc $(jemalloc-config --libs)" \
    USE_LUA=1 LUA_INC=/usr/local/include LUA_LIB=/usr/local/lib LUA_LIB_NAME=lua \
    USE_PCRE2_JIT=1 USE_STATIC_PCRE2=1 USE_SYSTEMD=1 \
    USE_OPENSSL=1 SSL_INC="/build_root/.openssl/include" SSL_LIB="/build_root/.openssl/lib" \
    USE_SLZ=1 SLZ_INC="/build_root/libslz/src" SLZ_LIB="/build_root/libslz" \
    CFLAGS="$CFLAGS -fPIE -Wl,-pie" \
    && checkinstall -y --nodoc --pkgversion="$haproxy_latest_tag_name" --install=no

FROM quay.io/icecodenew/alpine:edge AS haproxy-alpine-collection
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
# date +%s
ARG cachebust=1604512266
ARG haproxy_branch=2.2
ARG haproxy_latest_tag_name=2.2.4
ARG jemalloc_latest_tag_name=5.2.1
COPY --from=step3_jemalloc "/build_root/jemalloc/jemalloc_${jemalloc_latest_tag_name}-dev-1_amd64.deb" "/build_root/haproxy-${haproxy_branch}/jemalloc_${jemalloc_latest_tag_name}-dev-1_amd64.deb"
COPY --from=haproxy_builder "/build_root/haproxy-${haproxy_branch}/haproxy_${haproxy_latest_tag_name}-1_amd64.deb" "/build_root/haproxy-${haproxy_branch}/haproxy_${haproxy_latest_tag_name}-1_amd64.deb"
RUN apk update; apk --no-progress --no-cache add \
    bash coreutils curl findutils; \
    apk --no-progress --no-cache upgrade; \
    rm -rf /var/cache/apk/*
