FROM quay.io/icecodenew/builder_image_x86_64-linux:ubuntu AS step1_lua54
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
## curl -sSL "https://www.lua.org/download.html" | tr -d '\r\n\t' | grep -Po '(?<=lua-)[0-9]\.[0-9]\.[0-9](?=\.tar\.gz)' | sort -Vr | head -n 1
ARG lua_version='5.4.4'
ARG image_build_date='2022-03-08'
ARG dockerfile_workdir=/build_root/lua
WORKDIR $dockerfile_workdir
RUN curl --retry 5 --retry-delay 10 --retry-max-time 60 -fsSL "https://www.lua.org/ftp/lua-${lua_version}.tar.gz" | bsdtar -xf- --strip-components 1 --no-xattrs \
    && sed -i -E 's!MYCFLAGS=.*!MYCFLAGS='"$CFLAGS"' -fPIE -Wl,-pie!' src/Makefile \
    && make all test \
    && checkinstall -y --nodoc --pkgversion="$lua_version" \
    && rm -rf -- "$dockerfile_workdir"

FROM step1_lua54 AS step3_jemalloc
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# https://api.github.com/repos/jemalloc/jemalloc/releases/latest
ARG jemalloc_latest_tag_name='5.2.1'
# https://api.github.com/repos/jemalloc/jemalloc/commits?per_page=1
ARG jemalloc_latest_commit_hash='f6699803e2772de2a4eb253d5b55f00c3842a950'
ARG dockerfile_workdir=/build_root/jemalloc
WORKDIR $dockerfile_workdir
RUN git clone -j "$(nproc)" --no-tags --shallow-submodules --recurse-submodules --depth 1 --single-branch 'https://github.com/jemalloc/jemalloc.git' . \
    && CFLAGS="$CFLAGS -fPIC" \
    && CXXFLAGS="$CXXFLAGS -fPIC" \
    && export CFLAGS CXXFLAGS \
    && ./autogen.sh --prefix=/usr --disable-static \
    && make -j "$(nproc)" \
    && checkinstall -y --nodoc --pkgversion="${jemalloc_latest_tag_name}-dev" \
    && mv "./jemalloc_${jemalloc_latest_tag_name}-dev-1_amd64.deb" "/build_root/jemalloc_${jemalloc_latest_tag_name}-dev-1_amd64.deb" \
    && rm -rf -- "$dockerfile_workdir"

FROM step3_jemalloc AS haproxy_builder
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG haproxy_branch=2.4
## curl -sSL "https://git.haproxy.org/?p=haproxy-${haproxy_branch}.git;a=commit;h=refs/heads/master" | tr -d '\r\n\t' | grep -Po '(?<=<td>commit<\/td><td class="sha1">)[a-zA-Z0-9]+(?=<\/td>)'
ARG haproxy_latest_commit_hash='12460dbc67dedd1fef9dc81f59ee8154d9f6198f'
ARG haproxy_latest_tag_name='2.4.14'
ARG dockerfile_workdir=/build_root/haproxy
WORKDIR $dockerfile_workdir
RUN curl --retry 5 --retry-delay 10 --retry-max-time 60 -fsSL "https://git.haproxy.org/?p=haproxy-${haproxy_branch}.git;a=snapshot;h=${haproxy_latest_commit_hash};sf=tgz" | bsdtar -xf- --strip-components 1 --no-xattrs \
    && CFLAGS="$CFLAGS -fPIE -fwrapv" \
    && CXXFLAGS="$CXXFLAGS -fPIE -fwrapv" \
    && LDFLAGS="$LDFLAGS -pie" \
    && export CFLAGS CXXFLAGS LDFLAGS \
    && make clean \
    && make -j "$(nproc)" TARGET=linux-glibc \
    ADDLIB="-ljemalloc $(jemalloc-config --libs)" \
    USE_LUA=1 LUA_INC=/usr/local/include LUA_LIB=/usr/local/lib LUA_LIB_NAME=lua \
    USE_PCRE2_JIT=1 USE_STATIC_PCRE2=1 USE_SYSTEMD=1 \
    USE_PIE=1 USE_STACKPROTECTOR=1 USE_RELRO_NOW=1 \
    USE_OPENSSL=1 SSL_INC="/usr/include" SSL_LIB="/usr/lib64" \
    USE_PROMEX=1 \
    && checkinstall -y --nodoc --pkgversion="$haproxy_latest_tag_name" \
    && mv "./haproxy_${haproxy_latest_tag_name}-1_amd64.deb" "/build_root/haproxy_${haproxy_latest_tag_name}-1_amd64.deb" \
    && /usr/local/sbin/haproxy -vvv \
    && sed -E 's/@SBINDIR@/\/usr\/local\/sbin/g' 'admin/systemd/haproxy.service.in' > "/build_root/haproxy.service" \
    && rm -rf -- "$dockerfile_workdir"

FROM quay.io/icecodenew/alpine:latest AS haproxy-alpine-collection
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
ARG haproxy_branch=2.4
ARG haproxy_latest_tag_name=2.4.0
ARG jemalloc_latest_tag_name=5.2.1
COPY --from=step3_jemalloc "/build_root/jemalloc_${jemalloc_latest_tag_name}-dev-1_amd64.deb" "/build_root/"
COPY --from=haproxy_builder "/build_root/haproxy_${haproxy_latest_tag_name}-1_amd64.deb" "/build_root/haproxy.service" "/build_root/"
RUN apk update; apk --no-progress --no-cache add \
    bash coreutils curl findutils git; \
    apk --no-progress --no-cache upgrade; \
    rm -rf /var/cache/apk/*
