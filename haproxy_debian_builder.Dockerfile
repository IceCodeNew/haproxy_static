FROM ubuntu:devel AS base
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
# https://api.github.com/repos/slimm609/checksec.sh/releases/latest
ARG checksec_latest_tag_name='2.4.0'
# https://api.github.com/repos/IceCodeNew/myrc/commits?per_page=1&path=.bashrc
ARG bashrc_latest_commit_hash='dffed49d1d1472f1b22b3736a5c191d74213efaa'
# https://api.github.com/repos/Kitware/CMake/releases/latest
ARG cmake_latest_tag_name='v3.18.4'
# https://api.github.com/repos/ninja-build/ninja/releases/latest
ARG ninja_latest_tag_name='v1.10.1'
# https://api.github.com/repos/sabotage-linux/netbsd-curses/releases/latest
ARG netbsd_curses_tag_name='0.3.1'
# https://api.github.com/repos/sabotage-linux/gettext-tiny/releases/latest
ARG gettext_tiny_tag_name='0.3.2'
RUN apt-get update && apt-get -y --no-install-recommends install \
    apt-utils autoconf automake binutils build-essential ca-certificates checkinstall checksec cmake coreutils curl dos2unix git libarchive-tools libedit-dev libsystemd-dev libtool-bin lld locales musl-tools ncurses-bin ninja-build pkgconf util-linux \
    && apt-get -y full-upgrade \
    && apt-get clean && apt-get -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false purge \
    && rm -rf /var/lib/apt/lists/* \
    && sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen \
    && dpkg-reconfigure --frontend=noninteractive locales \
    && update-locale LANG=en_US.UTF-8 \
    && ( cd /usr || exit 1; curl -LROJ4q --retry 5 --retry-delay 10 --retry-max-time 60 "https://github.com/Kitware/CMake/releases/download/${cmake_latest_tag_name}/cmake-${cmake_latest_tag_name#v}-Linux-x86_64.sh" && bash "cmake-${cmake_latest_tag_name#v}-Linux-x86_64.sh" --skip-license && rm -f -- "/usr/cmake-${cmake_latest_tag_name#v}-Linux-x86_64.sh" '/usr/bin/cmake-gui' '/usr/bin/ctest' '/usr/bin/cpack' '/usr/bin/ccmake'; true ) \
    && ( curl -LROJ4q --retry 5 --retry-delay 10 --retry-max-time 60 "https://github.com/ninja-build/ninja/releases/download/${ninja_latest_tag_name}/ninja-linux.zip" && bsdtar -xf ninja-linux.zip && install -pvD "./ninja" "/usr/bin/" && rm -f -- './ninja' 'ninja-linux.zip' ) \
    # && update-ca-certificates \
    && update-alternatives --install /usr/local/bin/ld ld /usr/lib/llvm-9/bin/lld 100 \
    && update-alternatives --auto ld \
    # && for i in {1..2}; do checksec --update; done \
    && curl -sSL4q --retry 5 --retry-delay 10 --retry-max-time 60 -o '/root/.bashrc' "https://raw.githubusercontent.com/IceCodeNew/myrc/${bashrc_latest_commit_hash}/.bashrc" \
    && mkdir -p '/root/haproxy_static' \
    && mkdir -p '/usr/local/doc' \
    ### https://github.com/sabotage-linux/netbsd-curses
    && curl -sSLROJ --retry 5 --retry-delay 10 --retry-max-time 60 "http://ftp.barfooze.de/pub/sabotage/tarballs/netbsd-curses-${netbsd_curses_tag_name}.tar.xz" \
    && bsdtar -xf "netbsd-curses-${netbsd_curses_tag_name}.tar.xz" \
    && ( cd "/netbsd-curses-${netbsd_curses_tag_name}" || exit 1; make CFLAGS="$CFLAGS -fPIC" PREFIX=/usr -j "$(nproc)" all install ) \
    && rm -rf "/netbsd-curses-${netbsd_curses_tag_name}"* \
    ### https://github.com/sabotage-linux/gettext-tiny
    && curl -sSLROJ --retry 5 --retry-delay 10 --retry-max-time 60 "http://ftp.barfooze.de/pub/sabotage/tarballs/gettext-tiny-${gettext_tiny_tag_name}.tar.xz" \
    && bsdtar -xf "gettext-tiny-${gettext_tiny_tag_name}.tar.xz" \
    && ( cd "/gettext-tiny-${gettext_tiny_tag_name}" || exit 1; make CFLAGS="$CFLAGS -fPIC" PREFIX=/usr -j "$(nproc)" all install ) \
    && rm -rf "/gettext-tiny-${gettext_tiny_tag_name}"*

FROM base AS step1_pcre2
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG pcre2_version='10.35'
WORKDIR /root/haproxy_static
RUN source '/root/.bashrc' \
    && curl -sSROJ "https://ftp.pcre.org/pub/pcre/pcre2-${pcre2_version}.tar.bz2" \
    && bsdtar -xf "pcre2-${pcre2_version}.tar.bz2" && rm "pcre2-${pcre2_version}.tar.bz2"
WORKDIR "/root/haproxy_static/pcre2-${pcre2_version}"
RUN ./configure --enable-jit --enable-jit-sealloc \
    && make -j "$(nproc)" CFLAGS="$CFLAGS -mshstk -fPIC" \
    && make install

FROM step1_pcre2 AS step2_lua54
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG lua_version='5.4.0'
WORKDIR /root/haproxy_static
RUN source '/root/.bashrc' \
    && curl -sSROJ "https://www.lua.org/ftp/lua-${lua_version}.tar.gz" \
    && sha1sum "lua-${lua_version}.tar.gz" | grep '8cdbffa8a214a23d190d7c45f38c19518ae62e89' \
    && bsdtar -xf "lua-${lua_version}.tar.gz" && rm "lua-${lua_version}.tar.gz"
WORKDIR "/root/haproxy_static/lua-${lua_version}"
RUN make CFLAGS="$CFLAGS -fPIE -Wl,-pie" all test \
    && make install

FROM step2_lua54 AS step3_libslz
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG libslz_version='1.2.0'
WORKDIR /root/haproxy_static
RUN source '/root/.bashrc' \
    && curl -sSROJ "http://git.1wt.eu/web?p=libslz.git;a=snapshot;h=v${libslz_version};sf=tbz2" \
    && bsdtar -xf "libslz-v${libslz_version}.tar.bz2" && rm "libslz-v${libslz_version}.tar.bz2"
WORKDIR /root/haproxy_static/libslz
RUN sed -i -E 's!PREFIX     := \/usr\/local!PREFIX     := /usr!' Makefile \
    && make CFLAGS="$CFLAGS -fPIE -Wl,-pie" static

FROM step3_libslz AS step4_jemalloc
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# https://api.github.com/repos/jemalloc/jemalloc/releases/latest
ARG jemalloc_latest_tag_name='5.2.1'
WORKDIR /root/haproxy_static
RUN source '/root/.bashrc' \
    && var_icn_filename="jemalloc-${jemalloc_latest_tag_name}.tar.bz2" \
    && var_icn_download="https://github.com/jemalloc/jemalloc/releases/download/${jemalloc_latest_tag_name}/${var_icn_filename}" \
    && curl -sSR -o "$var_icn_filename" -- "$var_icn_download" \
    && bsdtar -xf "$var_icn_filename" && rm "$var_icn_filename"
WORKDIR "/root/haproxy_static/jemalloc-${jemalloc_latest_tag_name}"
RUN ./configure --prefix=/usr \
    && make -j "$(nproc)" CFLAGS="$CFLAGS -fPIC" \
    && make install

FROM step4_jemalloc AS step5_openssl
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
## curl 'https://raw.githubusercontent.com/openssl/openssl/OpenSSL_1_1_1-stable/README' | grep -Eo '1.1.1.*'
ARG openssl_latest_tag_name='1.1.1i-dev'
WORKDIR /root/haproxy_static
RUN source '/root/.bashrc' \
    && curl -sSROJ "https://github.com/openssl/openssl/archive/OpenSSL_1_1_1-stable.zip" \
    && mkdir "openssl-${openssl_latest_tag_name}" \
    && bsdtar -xf "openssl-OpenSSL_1_1_1-stable.zip" --strip-components 1 -C "openssl-${openssl_latest_tag_name}" && rm "openssl-OpenSSL_1_1_1-stable.zip"
WORKDIR "/root/haproxy_static/openssl-${openssl_latest_tag_name}"
RUN ./config --prefix="$(pwd -P)/.openssl" --release no-deprecated no-shared no-dtls1-method no-tls1_1-method no-sm2 no-sm3 no-sm4 no-rc2 no-rc4 threads CFLAGS="$CFLAGS -fPIC" CXXFLAGS="$CXXFLAGS -fPIC" LDFLAGS='-fuse-ld=lld' \
    && make -j "$(nproc)" CFLAGS="$CFLAGS -fPIE -Wl,-pie" CXXFLAGS="$CXXFLAGS -fPIE -Wl,-pie" \
    && make install_sw

FROM step5_openssl AS haproxy_builder
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG haproxy_branch='2.2'
## curl -sSL "https://git.haproxy.org/?p=haproxy-${haproxy_branch}.git;a=commit;h=refs/heads/master" | tr -d '\r\n\t' | grep -Po '(?<=<td>commit<\/td><td class="sha1">)[a-zA-Z0-9]+(?=<\/td>)'
ARG haproxy_latest_commit_hash='f495e5d6a597e2e1caa965e963ef16103da545db'
ARG openssl_latest_tag_name='1.1.1i-dev'
WORKDIR /root/haproxy_static
RUN source '/root/.bashrc' \
    && curl -sSR -o "haproxy-${haproxy_branch}.tar.gz" "https://git.haproxy.org/?p=haproxy-${haproxy_branch}.git;a=snapshot;h=${haproxy_latest_commit_hash};sf=tgz" \
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
    && checkinstall -y --nodoc --install=no
