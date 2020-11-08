FROM alpine:edge AS base
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
# https://api.github.com/repos/slimm609/checksec.sh/releases/latest
ARG checksec_latest_tag_name=2.4.0
# https://api.github.com/repos/IceCodeNew/myrc/commits?per_page=1&path=.bashrc
ARG bashrc_latest_commit_hash=dffed49d1d1472f1b22b3736a5c191d74213efaa
## curl -sSL "https://ftp.pcre.org/pub/pcre/" | tr -d '\r\n\t' | grep -Po '(?<=pcre2-)[0-9]+\.[0-9]+(?=\.tar\.bz2)' | sort -ru | head -n 1
ARG pcre2_version=10.35
## curl -sSL 'https://raw.githubusercontent.com/openssl/openssl/OpenSSL_1_1_1-stable/README' | grep -Eo '1.1.1.*'
ARG openssl_latest_tag_name=1.1.1i-dev
# https://api.github.com/repos/Kitware/CMake/releases/latest
ARG cmake_latest_tag_name=v3.18.4
# https://api.github.com/repos/ninja-build/ninja/releases/latest
ARG ninja_latest_tag_name=v1.10.1
# https://api.github.com/repos/sabotage-linux/netbsd-curses/releases/latest
ARG netbsd_curses_tag_name=0.3.1
# https://api.github.com/repos/sabotage-linux/gettext-tiny/releases/latest
ARG gettext_tiny_tag_name=0.3.2
RUN apk update; apk --no-progress --no-cache add \
    apk-tools autoconf automake bash binutils build-base ca-certificates clang-dev clang-static cmake coreutils curl dos2unix dpkg file gettext-tiny-dev git grep libarchive-tools libedit-dev libedit-static libtool linux-headers lld musl musl-dev musl-libintl musl-utils ncurses ncurses-dev ncurses-static openssl openssl-dev openssl-libs-static pcre2 pcre2-dev pcre2-tools perl pkgconf samurai util-linux; \
    apk --no-progress --no-cache upgrade; \
    rm -rf /var/cache/apk/*; \
    # update-alternatives --install /usr/local/bin/cc cc /usr/bin/clang 100; \
    # update-alternatives --install /usr/local/bin/c++ c++ /usr/bin/clang++ 100; \
    update-alternatives --install /usr/local/bin/ld ld /usr/bin/lld 100; \
    # update-alternatives --auto cc; \
    # update-alternatives --auto c++; \
    update-alternatives --auto ld; \
    curl -sSLR4q --retry 5 --retry-delay 10 --retry-max-time 60 -o '/root/.bashrc' "https://raw.githubusercontent.com/IceCodeNew/myrc/${bashrc_latest_commit_hash}/.bashrc"; \
    eval "$(sed -E '/^curl\(\)/!d' .bashrc)"; \
    curl -sS -o '/usr/bin/checksec' "https://raw.githubusercontent.com/slimm609/checksec.sh/${checksec_latest_tag_name}/checksec"; \
    chmod +x '/usr/bin/checksec'; \
    mkdir -p '/root/haproxy_static'

FROM base AS step1_lua54
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
## curl -sSL "https://www.lua.org/download.html" | tr -d '\r\n\t' | grep -Po '(?<=lua-)[0-9]\.[0-9]\.[0-9](?=\.tar\.gz)' | sort -ru | head -n 1
ARG lua_version=5.4.0
WORKDIR /root/haproxy_static
RUN source '/root/.bashrc' \
    && curl -sSOJ "https://www.lua.org/ftp/lua-${lua_version}.tar.gz" \
    && bsdtar -xf "lua-${lua_version}.tar.gz" && rm "lua-${lua_version}.tar.gz"
WORKDIR "/root/haproxy_static/lua-${lua_version}"
RUN make CFLAGS="$CFLAGS -fPIE -Wl,-pie" all test \
    && make install

FROM step1_lua54 AS step2_libslz
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
## curl -sSL "http://git.1wt.eu/web?p=libslz.git;a=commit;h=refs/heads/master" | tr -d '\r\n\t' | grep -Po '(?<=<td>commit<\/td><td class="sha1">)[a-zA-Z0-9]+(?=<\/td>)'
ARG libslz_latest_commit_hash='ff537154e7f5f2fffdbef1cd8c52b564c1b00067'
WORKDIR /root/haproxy_static
RUN source '/root/.bashrc' \
    && curl -sSOJ "http://git.1wt.eu/web?p=libslz.git;a=snapshot;h=${libslz_latest_commit_hash};sf=tbz2" \
    && bsdtar -xf "libslz-${libslz_latest_commit_hash}.tar.bz2" && rm "libslz-${libslz_latest_commit_hash}.tar.bz2"
WORKDIR /root/haproxy_static/libslz
RUN sed -i -E 's!PREFIX     := \/usr\/local!PREFIX     := /usr!' Makefile \
    && make CFLAGS="$CFLAGS -fPIE -Wl,-pie" static

FROM step2_libslz AS haproxy_builder
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG haproxy_branch=2.2
## curl -sSL "https://git.haproxy.org/?p=haproxy-${haproxy_branch}.git;a=commit;h=refs/heads/master" | tr -d '\r\n\t' | grep -Po '(?<=<td>commit<\/td><td class="sha1">)[a-zA-Z0-9]+(?=<\/td>)'
ARG haproxy_latest_commit_hash=aa3c7001cb32cd9c5bb7b5258459bb971e956438
WORKDIR /root/haproxy_static
RUN source '/root/.bashrc' \
    && curl -sS -o "haproxy-${haproxy_branch}.tar.gz" "https://git.haproxy.org/?p=haproxy-${haproxy_branch}.git;a=snapshot;h=${haproxy_latest_commit_hash};sf=tgz" \
    && mkdir "haproxy-${haproxy_branch}" \
    && bsdtar -xf "haproxy-${haproxy_branch}.tar.gz" --strip-components 1 -C "haproxy-${haproxy_branch}" && rm "haproxy-${haproxy_branch}.tar.gz" \
    && cd "haproxy-${haproxy_branch}" || exit 1 \
    && make clean \
    && make -j "$(nproc)" TARGET=linux-musl EXTRA_OBJS="contrib/prometheus-exporter/service-prometheus.o" \
    USE_LUA=1 LUA_INC=/usr/local/include LUA_LIB=/usr/local/lib LUA_LIB_NAME=lua \
    USE_PCRE2_JIT=1 USE_STATIC_PCRE2=1 \
    USE_OPENSSL=1 SSL_INC="/usr/include/openssl" SSL_LIB="/usr/lib" \
    USE_SLZ=1 SLZ_INC="/root/haproxy_static/libslz/src" SLZ_LIB="/root/haproxy_static/libslz" \
    CFLAGS="$CFLAGS -fPIE -Wl,-pie" LDFLAGS="$LDFLAGS -static-pie -nolibc -Wl,-Bstatic -L /usr/lib -l:libc.a" \
    && cp haproxy haproxy.ori \
    && strip haproxy

FROM alpine:edge AS haproxy-alpine-collection
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
# date +%s
ARG cachebust=1604512266
ARG haproxy_branch=2.2
ARG haproxy_latest_tag_name=2.2.4
COPY --from=haproxy_builder \
"/root/haproxy_static/haproxy-${haproxy_branch}/haproxy" \
"/root/haproxy_static/haproxy-${haproxy_branch}/haproxy.ori" \
"/root/haproxy_static/haproxy-${haproxy_branch}/"
RUN apk update; apk --no-progress --no-cache add \
    bash coreutils curl findutils; \
    apk --no-progress --no-cache upgrade; \
    rm -rf /var/cache/apk/*
