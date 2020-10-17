FROM debian/buildd:testing AS base
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ENV cmake_version="3.18.4"
ENV netbsd_curses_version="0.3.1"
ENV gettext_tiny_version="0.3.2"
RUN locale-gen en_US && update-locale LANG=en_US \
    && apt-get update && apt-get -y --no-install-recommends install \
    autoconf automake binutils build-essential ca-certificates checkinstall checksec cmake coreutils curl dos2unix git libarchive-tools libedit-dev libsystemd-dev libtool-bin lld musl-tools ncurses-bin ninja-build pkgconf util-linux \
    && apt-get clean && apt-get -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false purge \
    && rm -rf /var/lib/apt/lists/* \
    && ( cd /usr || exit 1; curl -LROJ4q --retry 5 --retry-delay 10 --retry-max-time 60 "https://github.com/Kitware/CMake/releases/download/v${cmake_version}/cmake-${cmake_version}-Linux-x86_64.sh" && bash "cmake-${cmake_version}-Linux-x86_64.sh" --skip-license && rm -- "/usr/cmake-${cmake_version}-Linux-x86_64.sh" /usr/bin/cmake-gui /usr/bin/ctest /usr/bin/cpack /usr/bin/ccmake; true ) \
    && ( curl -LROJ4q --retry 5 --retry-delay 10 --retry-max-time 60 "$(curl -sSL -H "Accept: application/vnd.github.v3+json" 'https://api.github.com/repos/ninja-build/ninja/releases/latest' | grep 'browser_download_url' | grep 'ninja-linux.zip' | cut -d\" -f4)" && bsdtar -xf ninja-linux.zip && rm /usr/bin/ninja ninja-linux.zip && mv ./ninja /usr/bin/ ) \
    && update-ca-certificates \
    && update-alternatives --install /usr/local/bin/ld ld /usr/lib/llvm-9/bin/lld 100 \
    && update-alternatives --auto ld \
    # && for i in {1..3}; do checksec --update; done; \
    curl -sSL4q --retry 5 --retry-delay 10 --retry-max-time 60 'https://raw.githubusercontent.com/IceCodeNew/myrc/main/.bashrc' > "/root/.bashrc" \
    && mkdir -p '/root/haproxy_static' \
    && mkdir -p '/usr/local/doc' \
    ### https://github.com/sabotage-linux/netbsd-curses
    && curl -sSLROJ --retry 5 --retry-delay 10 --retry-max-time 60 "http://ftp.barfooze.de/pub/sabotage/tarballs/netbsd-curses-${netbsd_curses_version}.tar.xz" \
    && bsdtar -xf "netbsd-curses-${netbsd_curses_version}.tar.xz" \
    && ( cd "/netbsd-curses-${netbsd_curses_version}" || exit 1; make CFLAGS="$CFLAGS -fPIC" PREFIX=/usr -j "$(nproc)" all install ) \
    && rm -rf "/netbsd-curses-${netbsd_curses_version}"* \
    ### https://github.com/sabotage-linux/gettext-tiny
    && curl -sSLROJ --retry 5 --retry-delay 10 --retry-max-time 60 "http://ftp.barfooze.de/pub/sabotage/tarballs/gettext-tiny-${gettext_tiny_version}.tar.xz" \
    && bsdtar -xf "gettext-tiny-${gettext_tiny_version}.tar.xz" \
    && ( cd "/gettext-tiny-${gettext_tiny_version}" || exit 1; make CFLAGS="$CFLAGS -fPIC" PREFIX=/usr -j "$(nproc)" all install ) \
    && rm -rf "/gettext-tiny-${gettext_tiny_version}"*

FROM base AS step1_pcre2
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV pcre2_version="10.35"
WORKDIR /root/haproxy_static
RUN source "/root/.bashrc" \
    && curl -sSROJ "https://ftp.pcre.org/pub/pcre/pcre2-${pcre2_version}.tar.bz2" \
    && bsdtar -xf "pcre2-${pcre2_version}.tar.bz2" && rm "pcre2-${pcre2_version}.tar.bz2"
WORKDIR "/root/haproxy_static/pcre2-${pcre2_version}"
RUN ./configure --enable-jit --enable-jit-sealloc \
    && make -j "$(nproc)" CFLAGS="$CFLAGS -mshstk -fPIC" \
    && make install

FROM step1_pcre2 AS step2_lua54
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV lua_version="5.4.0"
WORKDIR /root/haproxy_static
RUN source "/root/.bashrc" \
    && curl -sSROJ "https://www.lua.org/ftp/lua-${lua_version}.tar.gz" \
    && sha1sum "lua-${lua_version}.tar.gz" | grep '8cdbffa8a214a23d190d7c45f38c19518ae62e89' \
    && bsdtar -xf "lua-${lua_version}.tar.gz" && rm "lua-${lua_version}.tar.gz"
WORKDIR "/root/haproxy_static/lua-${lua_version}"
RUN make CFLAGS="$CFLAGS -fPIE -Wl,-pie" all test \
    && make install

FROM step2_lua54 AS step3_libslz
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV libslz_version="1.2.0"
WORKDIR /root/haproxy_static
RUN source "/root/.bashrc" \
    && curl -sSROJ "http://git.1wt.eu/web?p=libslz.git;a=snapshot;h=v${libslz_version};sf=tbz2" \
    && bsdtar -xf "libslz-v${libslz_version}.tar.bz2" && rm "libslz-v${libslz_version}.tar.bz2"
WORKDIR /root/haproxy_static/libslz
RUN sed -i -E 's!PREFIX     := \/usr\/local!PREFIX     := /usr!' Makefile \
    && make CFLAGS="$CFLAGS -fPIE -Wl,-pie" static

FROM step3_libslz AS step4_jemalloc
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR /root/haproxy_static
ENV jemalloc_version="5.2.1"
RUN source "/root/.bashrc" \
    && var_icn_download="https://github.com/jemalloc/jemalloc/releases/download/${jemalloc_version}/jemalloc-${jemalloc_version}.tar.bz2" \
    && var_icn_filename='jemalloc-'"$jemalloc_version" \
    && curl -sSR -o "$var_icn_filename"'.tar.bz2' -- "$var_icn_download" \
    && bsdtar -xf "$var_icn_filename"'.tar.bz2' && rm "$var_icn_filename"'.tar.bz2'
WORKDIR '/root/haproxy_static/jemalloc-'"$jemalloc_version"
RUN ./configure --prefix=/usr \
    && make -j "$(nproc)" CFLAGS="$CFLAGS -fPIC" \
    && make install

FROM step4_jemalloc AS step5_openssl
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR /root/haproxy_static
ENV openssl_github_tag="OpenSSL_1_1_1h"
RUN source "/root/.bashrc" \
    && curl -sSROJ 'https://github.com/openssl/openssl/archive/'"${openssl_github_tag}.tar.gz" \
    && bsdtar -xf "openssl-${openssl_github_tag}.tar.gz" && rm "openssl-${openssl_github_tag}.tar.gz"
WORKDIR "/root/haproxy_static/openssl-${openssl_github_tag}"
RUN ./config --prefix="$(pwd -P)/.openssl" --release no-deprecated no-shared no-dtls1-method no-tls1_1-method no-sm2 no-sm3 no-sm4 no-rc2 no-rc4 threads CFLAGS="$CFLAGS -fPIC" CXXFLAGS="$CXXFLAGS -fPIC" LDFLAGS='-fuse-ld=lld' \
    && make -j "$(nproc)" CFLAGS="$CFLAGS -fPIE -Wl,-pie" CXXFLAGS="$CXXFLAGS -fPIE -Wl,-pie" \
    && make install_sw

FROM step5_openssl AS haproxy_builder
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV haproxy_version="2.2.4"
ENV openssl_github_tag="OpenSSL_1_1_1h"
WORKDIR /root/haproxy_static
RUN source "/root/.bashrc" \
    && curl -sSROJ "https://www.haproxy.org/download/2.2/src/haproxy-${haproxy_version}.tar.gz" \
    && bsdtar -xf "haproxy-${haproxy_version}.tar.gz" && rm "haproxy-${haproxy_version}.tar.gz" \
    && cd "haproxy-${haproxy_version}" || exit 1 \
    && make clean \
    && make -j "$(nproc)" TARGET=linux-glibc EXTRA_OBJS="contrib/prometheus-exporter/service-prometheus.o" \
    ADDLIB="-ljemalloc $(jemalloc-config --libs)" \
    USE_LUA=1 LUA_INC=/usr/local/include LUA_LIB=/usr/local/lib LUA_LIB_NAME=lua \
    USE_PCRE2_JIT=1 USE_STATIC_PCRE2=1 USE_SYSTEMD=1 \
    USE_OPENSSL=1 SSL_INC="/root/haproxy_static/openssl-${openssl_github_tag}/.openssl/include" SSL_LIB="/root/haproxy_static/openssl-${openssl_github_tag}/.openssl/lib" \
    USE_SLZ=1 SLZ_INC="/root/haproxy_static/libslz/src" SLZ_LIB="/root/haproxy_static/libslz" \
    CFLAGS="$CFLAGS -fPIE -Wl,-pie" \
    && checkinstall -y --nodoc --install=no

FROM haproxy_builder AS haproxy_uploader
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV haproxy_version="2.2.4"
ENV GITHUB_TOKEN="set_your_github_token_here"
ARG LANG="en_US.utf-8"
ARG LC_ALL="en_US.utf-8"
RUN echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc \
    && echo 'export PATH=$PATH:"$HOME"/go/bin' >> ~/.bashrc \
    && source "/root/.bashrc" \
    && curl -LROJ 'https://dl.google.com/go/go1.15.2.linux-amd64.tar.gz' \
    && bsdtar -C /usr/local -xf 'go1.15.2.linux-amd64.tar.gz' && rm 'go1.15.2.linux-amd64.tar.gz'; \
    go env -w GOFLAGS="$GOFLAGS -buildmode=pie" \
    && go env -w CGO_CFLAGS="$CGO_CFLAGS -O2 -D_FORTIFY_SOURCE=2 -pipe -fexceptions -fstack-clash-protection -fstack-protector-strong -g -grecord-gcc-switches -Wl,-z,noexecstack,-z,relro,-z,now,-z,defs -Wl,--icf=all" \
    && go env -w CGO_CPPFLAGS="$CGO_CPPFLAGS -O2 -D_FORTIFY_SOURCE=2 -pipe -fexceptions -fstack-clash-protection -fstack-protector-strong -g -grecord-gcc-switches -Wl,-z,noexecstack,-z,relro,-z,now,-z,defs -Wl,--icf=all" \
    && go env -w CGO_CXXFLAGS="$CGO_CXXFLAGS -O2 -D_FORTIFY_SOURCE=2 -pipe -fexceptions -fstack-clash-protection -fstack-protector-strong -g -grecord-gcc-switches -Wl,-z,noexecstack,-z,relro,-z,now,-z,defs -Wl,--icf=all" \
    && go env -w CGO_LDFLAGS="$CGO_LDFLAGS -fuse-ld=lld -Wl,-z,noexecstack,-z,relro,-z,now,-z,defs -Wl,--icf=all" \
    # && go env -w GO111MODULE=on \
    # && go env -w GOPROXY=https://goproxy.cn,direct \
    && go get -u -v github.com/github-release/github-release \
    && mv -f "$HOME/go/bin"/* '/usr/local/bin' \
    && rm -r "$HOME/.cache/go-build" "$HOME/go"
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
