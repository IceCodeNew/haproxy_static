FROM alpine:edge AS base
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
RUN apk update; \
    apk --no-cache add apk-tools automake autoconf bash bash-completion binutils build-base clang-dev clang-static cmake coreutils ca-certificates curl dos2unix dpkg gettext-tiny-dev git grep libarchive-tools libedit-dev libedit-static libtool linux-headers lld musl-dev musl-libintl musl-utils ncurses ncurses-dev ncurses-static openssl openssl-dev openssl-libs-static pcre2 pcre2-dev pcre2-tools perl pkgconf samurai util-linux; \
    ### apk --no-cache add bat fd fzf go mlocate patch python3 python3-dev py3-pip util-linux-dev vim; \
    apk --no-cache upgrade; \
    update-alternatives --install /usr/local/bin/cc cc /usr/bin/clang 100; \
    update-alternatives --install /usr/local/bin/c++ c++ /usr/bin/clang++ 100; \
    update-alternatives --install /usr/local/bin/ld ld /usr/bin/lld 100; \
    update-alternatives --auto cc; \
    update-alternatives --auto c++; \
    update-alternatives --auto ld; \
    curl -sSL4q --retry 5 --retry-delay 10 --retry-max-time 60 -o '/usr/bin/checksec' 'https://raw.githubusercontent.com/slimm609/checksec.sh/master/checksec'; \
    chmod +x '/usr/bin/checksec'; \
    curl -sSL4q --retry 5 --retry-delay 10 --retry-max-time 60 -o '/root/.bashrc' 'https://raw.githubusercontent.com/IceCodeNew/myrc/main/.bashrc'; \
    mkdir -p "/root/haproxy_static"

FROM base AS step1_lua54
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR /root/haproxy_static
RUN source "/root/.bashrc" \
    && curl -sSROJ 'https://www.lua.org/ftp/lua-5.4.0.tar.gz' \
    && sha1check lua-5.4.0.tar.gz 8cdbffa8a214a23d190d7c45f38c19518ae62e89 \
    && bsdtar -xf lua-5.4.0.tar.gz && rm lua-5.4.0.tar.gz
WORKDIR /root/haproxy_static/lua-5.4.0
RUN make all test \
    && make install

FROM step1_lua54 AS step2_libslz
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR /root/haproxy_static
RUN source "/root/.bashrc" \
    && export libslz_version=1.2.0 \
    && curl -sSROJ "http://git.1wt.eu/web?p=libslz.git;a=snapshot;h=v${libslz_version};sf=tbz2" \
    && bsdtar -xf "libslz-v${libslz_version}.tar.bz2" && rm "libslz-v${libslz_version}.tar.bz2"
WORKDIR /root/haproxy_static/libslz
RUN sed -i -E 's!PREFIX     := \/usr\/local!PREFIX     := /usr!' Makefile \
    && make static

FROM step2_libslz AS haproxy_builder
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV haproxy_version="2.2.4"
WORKDIR /root/haproxy_static
RUN source "/root/.bashrc" \
    && curl -sSROJ "https://www.haproxy.org/download/2.2/src/haproxy-${haproxy_version}.tar.gz" \
    && bsdtar -xf "haproxy-${haproxy_version}.tar.gz" && rm "haproxy-${haproxy_version}.tar.gz" \
    && cd "haproxy-${haproxy_version}" || exit 1 \
    && make clean \
    && make -j "$(nproc)" TARGET=linux-musl EXTRA_OBJS="contrib/prometheus-exporter/service-prometheus.o" \
    USE_LUA=1 LUA_INC=/usr/local/include LUA_LIB=/usr/local/lib LUA_LIB_NAME=lua \
    USE_PCRE2_JIT=1 USE_STATIC_PCRE2=1 \
    USE_OPENSSL=1 SSL_INC="/usr/include/openssl" SSL_LIB="/usr/lib" \
    USE_SLZ=1 SLZ_INC="/root/haproxy_static/libslz/src" SLZ_LIB="/root/haproxy_static/libslz" \
    CC=clang LDFLAGS="-fuse-ld=lld -static-pie -static -nolibc -Wl,-Bstatic -L /usr/lib -l:libc.a"
