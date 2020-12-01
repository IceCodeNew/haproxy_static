FROM quay.io/icecodenew/ubuntu:latest AS base
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
# https://api.github.com/repos/slimm609/checksec.sh/releases/latest
ARG checksec_latest_tag_name=2.4.0
# https://api.github.com/repos/IceCodeNew/myrc/commits?per_page=1&path=.bashrc
ARG bashrc_latest_commit_hash=dffed49d1d1472f1b22b3736a5c191d74213efaa
# https://api.github.com/repos/Kitware/CMake/releases/latest
ARG cmake_latest_tag_name=v3.18.4
# https://api.github.com/repos/ninja-build/ninja/releases/latest
ARG ninja_latest_tag_name=v1.10.1
# https://api.github.com/repos/sabotage-linux/netbsd-curses/releases/latest
ARG netbsd_curses_tag_name=0.3.1
# https://api.github.com/repos/sabotage-linux/gettext-tiny/releases/latest
ARG gettext_tiny_tag_name=0.3.2
ENV PATH=/usr/lib/llvm-11/bin:$PATH
RUN apt-get update && apt-get -y --no-install-recommends install \
    apt-utils autoconf automake binutils build-essential ca-certificates checkinstall checksec cmake coreutils curl dos2unix git gpg gpg-agent libarchive-tools libedit-dev libsystemd-dev libtool-bin locales musl-tools ncurses-bin ninja-build pkgconf util-linux \
    && apt-get -y full-upgrade \
    && apt-get -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false purge \
    && curl -L 'https://apt.llvm.org/llvm-snapshot.gpg.key' | apt-key add - \
    && echo 'deb http://apt.llvm.org/focal/ llvm-toolchain-focal-11 main' > /etc/apt/sources.list.d/llvm.stable.list \
    && apt-get update && apt-get -y --install-recommends install \
    lld-11 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen \
    && dpkg-reconfigure --frontend=noninteractive locales \
    && update-locale LANG=en_US.UTF-8 \
    # && update-ca-certificates \
    # && for i in {1..2}; do checksec --update; done \
    && update-alternatives --install /usr/local/bin/ld ld /usr/lib/llvm-11/bin/lld 100 \
    && update-alternatives --auto ld \
    && curl -sSLR4q --retry 5 --retry-delay 10 --retry-max-time 60 -o '/root/.bashrc' "https://raw.githubusercontent.com/IceCodeNew/myrc/${bashrc_latest_commit_hash}/.bashrc" \
    && eval "$(sed -E '/^curl\(\)/!d' /root/.bashrc)" \
    && ( curl -OJ "https://github.com/ninja-build/ninja/releases/download/${ninja_latest_tag_name}/ninja-linux.zip" && bsdtar -xf ninja-linux.zip && install -pvD "./ninja" "/usr/bin/" && rm -f -- './ninja' 'ninja-linux.zip' ) \
    && ( cd /usr || exit 1; curl -OJ --compressed "https://github.com/Kitware/CMake/releases/download/${cmake_latest_tag_name}/cmake-${cmake_latest_tag_name#v}-Linux-x86_64.sh" && bash "cmake-${cmake_latest_tag_name#v}-Linux-x86_64.sh" --skip-license && rm -f -- "/usr/cmake-${cmake_latest_tag_name#v}-Linux-x86_64.sh" '/usr/bin/cmake-gui' '/usr/bin/ctest' '/usr/bin/cpack' '/usr/bin/ccmake'; true ) \
    && mkdir -p '/root/haproxy_static' \
    && mkdir -p '/usr/local/doc' \
    ### https://github.com/sabotage-linux/netbsd-curses
    && curl -sSOJ --compressed "http://ftp.barfooze.de/pub/sabotage/tarballs/netbsd-curses-${netbsd_curses_tag_name}.tar.xz" \
    && bsdtar -xf "netbsd-curses-${netbsd_curses_tag_name}.tar.xz" \
    && ( cd "/netbsd-curses-${netbsd_curses_tag_name}" || exit 1; make CFLAGS="$CFLAGS -fPIC" PREFIX=/usr -j "$(nproc)" all install ) \
    && rm -rf "/netbsd-curses-${netbsd_curses_tag_name}"* \
    ### https://github.com/sabotage-linux/gettext-tiny
    && curl -sSOJ --compressed "http://ftp.barfooze.de/pub/sabotage/tarballs/gettext-tiny-${gettext_tiny_tag_name}.tar.xz" \
    && bsdtar -xf "gettext-tiny-${gettext_tiny_tag_name}.tar.xz" \
    && ( cd "/gettext-tiny-${gettext_tiny_tag_name}" || exit 1; make CFLAGS="$CFLAGS -fPIC" PREFIX=/usr -j "$(nproc)" all install ) \
    && rm -rf "/gettext-tiny-${gettext_tiny_tag_name}"*

FROM base AS step1_pcre2
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
## curl -sSL "https://ftp.pcre.org/pub/pcre/" | tr -d '\r\n\t' | grep -Po '(?<=pcre2-)[0-9]+\.[0-9]+(?=\.tar\.bz2)' | sort -ru | head -n 1
ARG pcre2_version=10.35
WORKDIR /root/haproxy_static
RUN source '/root/.bashrc' \
    && curl -sSOJ "https://ftp.pcre.org/pub/pcre/pcre2-${pcre2_version}.tar.bz2" \
    && bsdtar -xf "pcre2-${pcre2_version}.tar.bz2" && rm "pcre2-${pcre2_version}.tar.bz2"
WORKDIR "/root/haproxy_static/pcre2-${pcre2_version}"
RUN ./configure --enable-jit --enable-jit-sealloc \
    && make -j "$(nproc)" CFLAGS="$CFLAGS -mshstk -fPIC" \
    && make install

FROM step1_pcre2 AS step2_lua54
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

FROM step2_lua54 AS step3_libslz
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

FROM step3_libslz AS step4_jemalloc
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# https://api.github.com/repos/jemalloc/jemalloc/releases/latest
ARG jemalloc_latest_tag_name=5.2.1
WORKDIR /root/haproxy_static
RUN source '/root/.bashrc' \
    && var_icn_filename="jemalloc-${jemalloc_latest_tag_name}.tar.bz2" \
    && var_icn_download="https://github.com/jemalloc/jemalloc/releases/download/${jemalloc_latest_tag_name}/${var_icn_filename}" \
    && curl -sS -o "$var_icn_filename" -- "$var_icn_download" \
    && bsdtar -xf "$var_icn_filename" && rm "$var_icn_filename"
WORKDIR "/root/haproxy_static/jemalloc-${jemalloc_latest_tag_name}"
RUN ./configure --prefix=/usr \
    && make -j "$(nproc)" CFLAGS="$CFLAGS -fPIC" \
    && checkinstall -y --nodoc --pkgversion="$jemalloc_latest_tag_name"

FROM step4_jemalloc AS step5_openssl
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# https://api.github.com/repos/openssl/openssl/commits?per_page=1&sha=OpenSSL_1_1_1-stable
ARG openssl_latest_commit_hash=25fa346e906c4f487727cfebd5a40740709e677b
## curl -sSL 'https://raw.githubusercontent.com/openssl/openssl/OpenSSL_1_1_1-stable/README' | grep -Eo '1.1.1.*'
ARG openssl_latest_tag_name=1.1.1i-dev
WORKDIR /root/haproxy_static
RUN source '/root/.bashrc' \
    && curl -sSOJ "https://github.com/openssl/openssl/archive/OpenSSL_1_1_1-stable.zip" \
    && mkdir "openssl-${openssl_latest_tag_name}" \
    && bsdtar -xf "openssl-OpenSSL_1_1_1-stable.zip" --strip-components 1 -C "openssl-${openssl_latest_tag_name}" && rm "openssl-OpenSSL_1_1_1-stable.zip"
WORKDIR "/root/haproxy_static/openssl-${openssl_latest_tag_name}"
RUN ./config --prefix="$(pwd -P)/.openssl" --release no-deprecated no-shared no-dtls1-method no-tls1_1-method no-sm2 no-sm3 no-sm4 no-rc2 no-rc4 threads CFLAGS="$CFLAGS -fPIC" CXXFLAGS="$CXXFLAGS -fPIC" LDFLAGS='-fuse-ld=lld' \
    && make -j "$(nproc)" CFLAGS="$CFLAGS -fPIE -Wl,-pie" CXXFLAGS="$CXXFLAGS -fPIE -Wl,-pie" \
    && make install_sw

FROM step5_openssl AS haproxy_builder
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG haproxy_branch=2.2
## curl -sSL "https://git.haproxy.org/?p=haproxy-${haproxy_branch}.git;a=commit;h=refs/heads/master" | tr -d '\r\n\t' | grep -Po '(?<=<td>commit<\/td><td class="sha1">)[a-zA-Z0-9]+(?=<\/td>)'
ARG haproxy_latest_commit_hash=aa3c7001cb32cd9c5bb7b5258459bb971e956438
ARG haproxy_latest_tag_name=2.2.4
ARG openssl_latest_tag_name=1.1.1i-dev
WORKDIR /root/haproxy_static
RUN source '/root/.bashrc' \
    && curl -sS -o "haproxy-${haproxy_branch}.tar.gz" "https://git.haproxy.org/?p=haproxy-${haproxy_branch}.git;a=snapshot;h=${haproxy_latest_commit_hash};sf=tgz" \
    && mkdir "haproxy-${haproxy_branch}" \
    && bsdtar -xf "haproxy-${haproxy_branch}.tar.gz" --strip-components 1 -C "haproxy-${haproxy_branch}" && rm "haproxy-${haproxy_branch}.tar.gz" \
    && cd "haproxy-${haproxy_branch}" || exit 1 \
    && make clean \
    && make -j "$(nproc)" TARGET=linux-glibc EXTRA_OBJS="contrib/prometheus-exporter/service-prometheus.o" \
    ADDLIB="-ljemalloc $(jemalloc-config --libs)" \
    USE_LUA=1 LUA_INC=/usr/local/include LUA_LIB=/usr/local/lib LUA_LIB_NAME=lua \
    USE_PCRE2_JIT=1 USE_STATIC_PCRE2=1 USE_SYSTEMD=1 \
    USE_OPENSSL=1 SSL_INC="/root/haproxy_static/openssl-${openssl_latest_tag_name}/.openssl/include" SSL_LIB="/root/haproxy_static/openssl-${openssl_latest_tag_name}/.openssl/lib" \
    USE_SLZ=1 SLZ_INC="/root/haproxy_static/libslz/src" SLZ_LIB="/root/haproxy_static/libslz" \
    CFLAGS="$CFLAGS -fPIE -Wl,-pie" \
    && checkinstall -y --nodoc --pkgversion="$haproxy_latest_tag_name" --install=no

FROM quay.io/icecodenew/alpine:edge AS haproxy-alpine-collection
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
# date +%s
ARG cachebust=1604512266
ARG haproxy_branch=2.2
ARG haproxy_latest_tag_name=2.2.4
ARG jemalloc_latest_tag_name=5.2.1
COPY --from=step4_jemalloc "/root/haproxy_static/jemalloc-${jemalloc_latest_tag_name}/jemalloc_${jemalloc_latest_tag_name}-1_amd64.deb" "/root/haproxy_static/haproxy-${haproxy_branch}/jemalloc_${jemalloc_latest_tag_name}-1_amd64.deb"
COPY --from=haproxy_builder "/root/haproxy_static/haproxy-${haproxy_branch}/haproxy_${haproxy_latest_tag_name}-1_amd64.deb" "/root/haproxy_static/haproxy-${haproxy_branch}/haproxy_${haproxy_latest_tag_name}-1_amd64.deb"
RUN apk update; apk --no-progress --no-cache add \
    bash coreutils curl findutils; \
    apk --no-progress --no-cache upgrade; \
    rm -rf /var/cache/apk/*
