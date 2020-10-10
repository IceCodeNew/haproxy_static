FROM debian/buildd:testing AS base
SHELL ["/bin/bash", "-c"]
RUN apt-get update && apt-get -y install \
    automake autoconf binutils build-essential coreutils ca-certificates curl dos2unix git libarchive-tools libtool-bin lld musl-tools ncurses-bin pkgconf util-linux --no-install-recommends \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
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
    && rm -rf /gettext-tiny-0.3.2*
    ### https://www.thrysoee.dk/editline/
    && curl -sSLROJ --retry 5 --retry-delay 10 --retry-max-time 60 'https://www.thrysoee.dk/editline/libedit-20191231-3.1.tar.gz' \
    && bsdtar -xf 'libedit-20191231-3.1.tar.gz' \
    && ( cd /libedit-20191231-3.1 || exit 1; curl -sSLROJ --retry 5 --retry-delay 10 --retry-max-time 60 'https://raw.githubusercontent.com/sabotage-linux/sabotage/master/KEEP/libedit_readlineh.patch' && patch -p1 < ./libedit_readlineh.patch && CFLAGS='-Os -Wall -fPIC' LDFLAGS='-fuse-ld=lld' ./configure -C --prefix='/usr' --enable-widec && make -j "$(nproc)" V=1 && make install && ln -sf /usr/lib/libedit.a /usr/lib/libreadline.a && ln -sf /usr/lib/libedit.so /usr/lib/libreadline.so && mkdir -p /usr/include/readline && touch /usr/include/readline/history.h && touch /usr/include/readline/tilde.h && ln -sf /usr/include/editline/readline.h /usr/include/readline/readline.h ) \
    && rm -rf /libedit-20191231-3.1*
