FROM debian:bullseye as openssl

ENV VERSION_OPENSSL=openssl-3.1.0 \
    SHA256_OPENSSL=aaa925ad9828745c4cad9d9efeb273deca820f2cdcf2c3ac7d7c1212b7c497b4 \
    SOURCE_OPENSSL=https://www.openssl.org/source/ \
    OPGP_OPENSSL=8657ABB260F056B1E5190839D9C4D26D0E604491

WORKDIR /tmp/src

RUN set -e -x && \
    build_deps="build-essential ca-certificates curl dirmngr gnupg libidn2-0-dev libssl-dev" && \
    DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y --no-install-recommends \
      $build_deps && \
    curl -L $SOURCE_OPENSSL$VERSION_OPENSSL.tar.gz -o openssl.tar.gz && \
    echo "${SHA256_OPENSSL} ./openssl.tar.gz" | sha256sum -c - && \
    curl -L $SOURCE_OPENSSL$VERSION_OPENSSL.tar.gz.asc -o openssl.tar.gz.asc && \
    GNUPGHOME="$(mktemp -d)" && \
    export GNUPGHOME && \
    gpg --no-tty --keyserver keyserver.ubuntu.com --recv-keys "$OPGP_OPENSSL" && \
    gpg --batch --verify openssl.tar.gz.asc openssl.tar.gz && \
    tar xzf openssl.tar.gz && \
    cd $VERSION_OPENSSL && \
    ./Configure linux-x32 && \
    ./config \
      --prefix=/opt/openssl \
      --openssldir=/opt/openssl \
      no-weak-ssl-ciphers \
      no-ssl3 \
      no-shared \
      -DOPENSSL_NO_HEARTBEATS \
      -fstack-protector-strong && \
    make depend && \
    nproc | xargs -I % make -j% && \
    make install_sw && \
    apt-get purge -y --auto-remove \
      $build_deps && \
    rm -rf \
        /tmp/* \
        /var/tmp/* \
        /var/lib/apt/lists/*

FROM debian:bullseye as unbound

ENV NAME=unbound \
    UNBOUND_VERSION=1.17.1 \
    UNBOUND_SHA256=ee4085cecce12584e600f3d814a28fa822dfaacec1f94c84bfd67f8a5571a5f4 \
    UNBOUND_DOWNLOAD_URL=https://nlnetlabs.nl/downloads/unbound/unbound-1.17.1.tar.gz

WORKDIR /tmp/src

COPY --from=openssl /opt/openssl /opt/openssl

RUN build_deps="curl gcc libc-dev libevent-dev libexpat1-dev libnghttp2-dev make" && \
    set -x && \
    DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y --no-install-recommends \
      $build_deps \
      bsdmainutils \
      ca-certificates \
      ldnsutils \
      libevent-2.1-7 \
      libexpat1 && \
    curl -sSL $UNBOUND_DOWNLOAD_URL -o unbound.tar.gz && \
    echo "${UNBOUND_SHA256} *unbound.tar.gz" | sha256sum -c - && \
    tar xzf unbound.tar.gz && \
    rm -f unbound.tar.gz && \
    cd unbound-1.17.1 && \
    groupadd _unbound && \
    useradd -g _unbound -s /etc -d /dev/null _unbound && \
    ./configure \
        --disable-dependency-tracking \
        --prefix=/opt/unbound \
        --with-pthreads \
        --with-username=_unbound \
        --with-ssl=/opt/openssl \
        --with-libevent \
        --with-libnghttp2 \
        --enable-tfo-server \
        --enable-tfo-client \
        --enable-event-api && \
    make install && \
    mv /opt/unbound/etc/unbound/unbound.conf /opt/unbound/etc/unbound/unbound.conf.example && \
    apt-get purge -y --auto-remove \
      $build_deps && \
    rm -rf \
        /opt/unbound/share/man \
        /tmp/* \
        /var/tmp/* \
        /var/lib/apt/lists/*

FROM debian:bullseye

WORKDIR /tmp/src

COPY --from=unbound /opt /opt

RUN set -x && \
    DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y --no-install-recommends \
      bsdmainutils \
      ca-certificates \
      ldnsutils \
      libevent-2.1-7 \
      libnghttp2-14 \
      libexpat1 && \
    groupadd _unbound && \
    useradd -g _unbound -s /etc -d /dev/null _unbound && \
    apt-get purge -y --auto-remove \
      $build_deps && \
    rm -rf \
        /opt/unbound/share/man \
        /tmp/* \
        /var/tmp/* \
        /var/lib/apt/lists/*

COPY data/ /

RUN chmod +x /unbound.sh

WORKDIR /opt/unbound/

ENV PATH /opt/unbound/sbin:"$PATH"

LABEL org.opencontainers.image.version=${UNBOUND_VERSION} \
      org.opencontainers.image.title="techblog/unbound" \
      org.opencontainers.image.description="a validating, recursive, and caching DNS resolver" \
      org.opencontainers.image.url="https://github.com/t0mer/unbound-docker" \
      org.opencontainers.image.vendor="Tomer Klein" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.source="https://github.com/t0mer/unbound-docker"

EXPOSE 53/tcp
EXPOSE 53/udp

HEALTHCHECK --interval=30s --timeout=30s --start-period=10s --retries=3 CMD drill @127.0.0.1 cloudflare.com || exit 1

CMD ["/unbound.sh"]