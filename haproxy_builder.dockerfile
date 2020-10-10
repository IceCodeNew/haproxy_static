FROM debian/buildd:testing AS base
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN apt-get update && apt-get -y install \
    automake autoconf binutils build-essential cmake coreutils ca-certificates curl dos2unix git libarchive-tools libtool-bin libsystemd-dev lld musl-tools ncurses-bin ninja-build pkgconf util-linux --no-install-recommends \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    # && ( cd /usr || exit 1; cmake_version=$(curl -sSL -H "Accept: application/vnd.github.v3+json" 'https://api.github.com/repos/Kitware/CMake/tags?per_page=32' | grep 'name' | cut -d\" -f4 | grep -oEm1 '3\.18\.[0-9]+') && curl -LROJ4q --retry 5 --retry-delay 10 --retry-max-time 60 "https://github.com/Kitware/CMake/releases/download/v${cmake_version}/cmake-${cmake_version}-Linux-x86_64.sh" && bash "cmake-${cmake_version}-Linux-x86_64.sh" --skip-license && rm -- /usr/"cmake-${cmake_version}-Linux-x86_64.sh" /usr/bin/cmake-gui /usr/bin/ctest /usr/bin/cpack /usr/bin/ccmake; true ) \
    # && ( curl -LROJ4q --retry 5 --retry-delay 10 --retry-max-time 60 "$(curl -sL 'https://api.github.com/repos/ninja-build/ninja/releases/latest' | grep 'browser_download_url' | grep 'ninja-linux.zip' | cut -d\" -f4)" && bsdtar xf ninja-linux.zip && rm /usr/bin/ninja && mv ./ninja /usr/bin/ && rm ninja-linux.zip ) \
    && update-ca-certificates \
    && update-alternatives --install /usr/local/bin/ld ld /usr/lib/llvm-9/bin/lld 100 \
    && update-alternatives --auto ld \
    && curl -sSL4q --retry 5 --retry-delay 10 --retry-max-time 60 'https://raw.githubusercontent.com/IceCodeNew/myrc/main/.bashrc' > "${HOME}/.bashrc" \
    && mkdir -p "${HOME}/haproxy_static" \
    ### https://github.com/sabotage-linux/netbsd-curses
    && curl -sSLROJ --retry 5 --retry-delay 10 --retry-max-time 60 'http://ftp.barfooze.de/pub/sabotage/tarballs/netbsd-curses-0.3.1.tar.xz' \
    && bsdtar -xf 'netbsd-curses-0.3.1.tar.xz' \
    && ( cd /netbsd-curses-0.3.1 || exit 1; make CFLAGS='-Os -Wall -fPIC' LDFLAGS='-fuse-ld=lld' PREFIX=/usr -j "$(nproc)" all install ) \
    && rm -rf /netbsd-curses-0.3.1* \
    ### https://github.com/sabotage-linux/gettext-tiny
    && curl -sSLROJ --retry 5 --retry-delay 10 --retry-max-time 60 'http://ftp.barfooze.de/pub/sabotage/tarballs/gettext-tiny-0.3.2.tar.xz' \
    && bsdtar -xf 'gettext-tiny-0.3.2.tar.xz' \
    && ( cd /gettext-tiny-0.3.2 || exit 1; make CFLAGS='-Os -Wall -fPIC' LDFLAGS='-fuse-ld=lld' PREFIX=/usr -j "$(nproc)" all install ) \
    && rm -rf /gettext-tiny-0.3.2* \
    ### https://github.com/AmokHuginnsson/replxx
    && curl -sSLROJ --retry 5 --retry-delay 10 --retry-max-time 60 'https://github.com/AmokHuginnsson/replxx/archive/master.zip' \
    && bsdtar -xf 'replxx-master.zip' \
    && ( mkdir -p /replxx-master/build && cd /replxx-master/build || exit 1; cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON -DREPLXX_BUILD_EXAMPLES=OFF .. && make CFLAGS='-Os -Wall -fPIC' LDFLAGS='-fuse-ld=lld' -j "$(nproc)" && make install && rm -r /replxx-master/build ) \
    && ( mkdir -p /replxx-master/build && cd /replxx-master/build || exit 1; cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DREPLXX_BUILD_EXAMPLES=ON .. && make CFLAGS='-Os -Wall -fPIC' LDFLAGS='-fuse-ld=lld' -j "$(nproc)" && make install ) \
    && ( ln -sf /usr/local/lib/libreplxx.a /usr/lib/libreadline.a && ln -sf /usr/local/lib/libreplxx.so /usr/lib/libreadline.so && mkdir -p /usr/include/readline && touch /usr/include/readline/history.h && touch /usr/include/readline/tilde.h && ln -sf /usr/include/editline/readline.h /usr/include/readline/readline.h ) \
    && rm -rf /replxx-master*

FROM base AS step1_pcre2
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR "${HOME}/haproxy_static"
RUN source "${HOME}/.bashrc" \
    && curl -sSROJ 'https://ftp.pcre.org/pub/pcre/pcre2-10.35.tar.bz2' \
    && bsdtar -xf pcre2-10.35.tar.bz2 && rm pcre2-10.35.tar.bz2
WORKDIR pcre2-10.35
RUN ./configure --enable-jit --enable-jit-sealloc \
    && make -j "$(nproc)" CFLAGS='-mshstk' \
    && make install

FROM step1_pcre2 AS step2_lua54
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR "${HOME}/haproxy_static"
RUN source "${HOME}/.bashrc" \
    && curl -sSROJ 'https://www.lua.org/ftp/lua-5.4.0.tar.gz' \
    && sha1check lua-5.4.0.tar.gz 8cdbffa8a214a23d190d7c45f38c19518ae62e89 \
    && bsdtar -xf lua-5.4.0.tar.gz && rm lua-5.4.0.tar.gz
WORKDIR lua-5.4.0
RUN make all test \
    && make install

FROM step2_lua54 AS step3_libslz
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR "${HOME}/haproxy_static"
RUN source "${HOME}/.bashrc" \
    && export libslz_version=1.2.0 \
    && curl -sSROJ "http://git.1wt.eu/web?p=libslz.git;a=snapshot;h=v${libslz_version};sf=tbz2" \
    && bsdtar -xf "libslz-v${libslz_version}.tar.bz2" && rm "libslz-v${libslz_version}.tar.bz2"
WORKDIR libslz
RUN sed -i -E 's!PREFIX     := \/usr\/local!PREFIX     := /usr!' Makefile \
    && make static

FROM step3_libslz AS step4_jemalloc
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR "${HOME}/haproxy_static"
RUN source "${HOME}/.bashrc" \
    && var_icn_download=$(curl -sL https://api.github.com/repos/jemalloc/jemalloc/releases/latest | grep 'browser_download_url' | grep -i 'tar.bz2' | cut -d\" -f4) \
    && var_icn_filename='jemalloc-'"$(echo "$var_icn_download" | grep -Po '(?<=releases\/download\/)[^\/]+')" \
    && curl -sSR -o "$var_icn_filename"'.tar.bz2' -- "$var_icn_download" \
    && bsdtar -xf "$var_icn_filename"'.tar.bz2' && rm "$var_icn_filename"'.tar.bz2'
WORKDIR "$var_icn_filename"
RUN ./configure --prefix=/usr \
    && make -j "$(nproc)" \
    && make install

FROM step4_jemalloc AS step5_openssl
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR "${HOME}/haproxy_static"
RUN source "${HOME}/.bashrc" \
    && openssl_github_tag=$(curl -H "Accept: application/vnd.github.v3+json" -sSL 'https://api.github.com/repos/openssl/openssl/tags?per_page=32' | grep 'name' | cut -d\" -f4 | grep -Em1 'OpenSSL_1_1_[0-9][a-z]') \
    && curl -sSROJ 'https://github.com/openssl/openssl/archive/'"${openssl_github_tag}.tar.gz" \
    && bsdtar -xf "openssl-${openssl_github_tag}.tar.gz" && rm "openssl-${openssl_github_tag}.tar.gz"
WORKDIR "openssl-${openssl_github_tag}"
RUN ./config --prefix="$(pwd -P)/.openssl" no-shared \
    && make -j "$(nproc)" && make install_sw
