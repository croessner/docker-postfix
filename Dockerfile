# syntax=docker/dockerfile:1.7
ARG BUILDKIT_SBOM_SCAN_CONTEXT=true
ARG BUILDKIT_SBOM_SCAN_STAGE=true

ARG ALPINE_VERSION=3.23
ARG POSTFIX_VERSION=3.11.5
ARG POSTFIX_SHA256=4a6ab3d0e9390989fa201fc6c446045fc702c4e16e7a247c3ae261c9e9bee610
ARG POSTFIX_SOURCE_URL=http://ftp.porcupine.org/mirrors/postfix-release/official/postfix-${POSTFIX_VERSION}.tar.gz
ARG TLSRPT_VERSION=0.5.0
ARG TLSRPT_GIT_TAG=v${TLSRPT_VERSION}
ARG TINYCDB_VERSION=0.81
ARG TINYCDB_SHA256=469de2d445bf54880f652f4b6dc95c7cdf6f5502c35524a45b2122d70d47ebc2
ARG TINYCDB_SOURCE_URL=https://www.corpit.ru/mjt/tinycdb/tinycdb-${TINYCDB_VERSION}.tar.gz
ARG OCI_SOURCE="https://github.com/croessner/docker-postfix"
ARG OCI_URL="https://hub.docker.com/r/chrroessner/postfix"
ARG OCI_DOCUMENTATION="https://github.com/croessner/docker-postfix#readme"
ARG OCI_VENDOR="Rößner-Network-Solutions"
ARG OCI_AUTHORS="Christian Rößner <christian@roessner.email>"
ARG OCI_LICENSES="MIT AND IPL-1.0 AND LGPL-3.0-or-later AND BSD-4-Clause-UC"
ARG OCI_VERSION="dev"
ARG OCI_REVISION="unknown"

FROM --platform=$TARGETPLATFORM alpine:${ALPINE_VERSION} AS builder

ARG POSTFIX_VERSION
ARG POSTFIX_SHA256
ARG POSTFIX_SOURCE_URL
ARG TLSRPT_GIT_TAG
ARG TINYCDB_SHA256
ARG TINYCDB_SOURCE_URL

LABEL org.opencontainers.image.title="Postfix Alpine" \
      org.opencontainers.image.description="Postfix built from pinned source on Alpine Linux with dynamic map support, env-driven configuration, custom config overlays, and TLSRPT support" \
      org.opencontainers.image.licenses="IPL-1.0 AND LGPL-3.0-or-later AND BSD-4-Clause-UC"

RUN apk upgrade --no-cache \
    && apk add --no-cache \
        autoconf \
        automake \
        build-base \
        ca-certificates \
        coreutils \
        curl \
        cyrus-sasl-dev \
        db-dev \
        git \
        icu-dev \
        libmemcached-dev \
        libnsl-dev \
        libpq \
        libpq-dev \
        libtool \
        linux-headers \
        libtirpc-dev \
        lmdb-dev \
        mariadb-connector-c-dev \
        mongo-c-driver-dev \
        openldap-dev \
        openssl-dev \
        pcre2-dev \
        pkgconf \
        rpcsvc-proto-dev \
        sqlite-dev \
        tar

WORKDIR /tmp/build

RUN curl -fsSLo postfix.tgz "${POSTFIX_SOURCE_URL}" \
    && if [ -n "${POSTFIX_SHA256}" ]; then \
         echo "${POSTFIX_SHA256}  postfix.tgz" | sha256sum -c -; \
       fi \
    && tar -xzf postfix.tgz \
    && mv "postfix-${POSTFIX_VERSION}" postfix

RUN git clone --depth 1 --branch "${TLSRPT_GIT_TAG}" https://github.com/sys4/libtlsrpt.git libtlsrpt \
    && curl -fsSLo tinycdb.tgz "${TINYCDB_SOURCE_URL}" \
    && if [ -n "${TINYCDB_SHA256}" ]; then \
         echo "${TINYCDB_SHA256}  tinycdb.tgz" | sha256sum -c -; \
       fi \
    && tar -xzf tinycdb.tgz \
    && mv "tinycdb-"* tinycdb

WORKDIR /tmp/build/libtlsrpt

RUN autoreconf --verbose --install --force \
    && ./configure --prefix=/usr/local \
    && make -j"$(getconf _NPROCESSORS_ONLN)" \
    && make install

WORKDIR /tmp/build/tinycdb

RUN make -j"$(getconf _NPROCESSORS_ONLN)" \
    && make PREFIX=/usr/local install

WORKDIR /tmp/build/postfix

RUN export CCARGS="$(pcre2-config --cflags) -DUSE_TLS -DUSE_SASL_AUTH -DUSE_CYRUS_SASL -DUSE_LDAP_SASL -DUSE_TLSRPT -I/usr/include/sasl -I/usr/include/tirpc -I/usr/local/include -DHAS_CDB -DHAS_LMDB -DHAS_LDAP -DHAS_MYSQL -I/usr/include/mysql -DHAS_PGSQL -I/usr/include/postgresql -DHAS_SQLITE -DHAS_MONGODB -I/usr/include/libmongoc-1.0 -I/usr/include/libbson-1.0 -DHAS_PCRE=2" \
    && export AUXLIBS="-lssl -lcrypto -lsasl2 -lnsl -ltirpc -L/usr/local/lib -Wl,-rpath,/usr/local/lib -ltlsrpt -ldb" \
    && export AUXLIBS_CDB="-L/usr/local/lib -lcdb" \
    && export AUXLIBS_LDAP="-lldap -llber" \
    && export AUXLIBS_LMDB="-llmdb -lpthread" \
    && export AUXLIBS_MYSQL="-lmariadb" \
    && export AUXLIBS_MONGODB="-lmongoc-1.0 -lbson-1.0" \
    && export AUXLIBS_PCRE="$(pcre2-config --libs8)" \
    && export AUXLIBS_PGSQL="-lpq" \
    && export AUXLIBS_SQLITE="-lsqlite3 -lpthread" \
    && make -f Makefile.init makefiles \
         shared=yes \
         dynamicmaps=yes \
         pie=yes \
         CCARGS="${CCARGS}" \
         AUXLIBS="${AUXLIBS}" \
         AUXLIBS_CDB="${AUXLIBS_CDB}" \
         AUXLIBS_LDAP="${AUXLIBS_LDAP}" \
         AUXLIBS_LMDB="${AUXLIBS_LMDB}" \
         AUXLIBS_MYSQL="${AUXLIBS_MYSQL}" \
         AUXLIBS_MONGODB="${AUXLIBS_MONGODB}" \
         AUXLIBS_PCRE="${AUXLIBS_PCRE}" \
         AUXLIBS_PGSQL="${AUXLIBS_PGSQL}" \
         AUXLIBS_SQLITE="${AUXLIBS_SQLITE}" \
         config_directory=/etc/postfix \
         command_directory=/usr/sbin \
         daemon_directory=/usr/libexec/postfix \
         data_directory=/var/lib/postfix \
         meta_directory=/etc/postfix \
         queue_directory=/var/spool/postfix \
         sendmail_path=/usr/sbin/sendmail \
         newaliases_path=/usr/bin/newaliases \
         mailq_path=/usr/bin/mailq \
         shlib_directory=/usr/lib/postfix \
         html_directory=no \
         manpage_directory=/usr/share/man \
         sample_directory=/etc/postfix \
         readme_directory=no \
    && make -j"$(getconf _NPROCESSORS_ONLN)" \
    && make non-interactive-package \
         install_root=/tmp/out \
         config_directory=/etc/postfix \
         command_directory=/usr/sbin \
         daemon_directory=/usr/libexec/postfix \
         data_directory=/var/lib/postfix \
         meta_directory=/etc/postfix \
         queue_directory=/var/spool/postfix \
         sendmail_path=/usr/sbin/sendmail \
         newaliases_path=/usr/bin/newaliases \
         mailq_path=/usr/bin/mailq \
         shlib_directory=/usr/lib/postfix \
         mail_owner=postfix \
         setgid_group=postdrop \
         html_directory=no \
         manpage_directory=/usr/share/man \
         sample_directory=/etc/postfix \
         readme_directory=no \
    && mkdir -p /tmp/default-config \
    && cp conf/main.cf /tmp/default-config/main.cf \
    && cp conf/master.cf /tmp/default-config/master.cf \
    && cp /tmp/out/etc/postfix/dynamicmaps.cf /tmp/default-config/dynamicmaps.cf

FROM --platform=$TARGETPLATFORM alpine:${ALPINE_VERSION}

ARG ALPINE_VERSION
ARG POSTFIX_VERSION
ARG TLSRPT_VERSION
ARG TINYCDB_VERSION
ARG OCI_SOURCE
ARG OCI_URL
ARG OCI_DOCUMENTATION
ARG OCI_VENDOR
ARG OCI_AUTHORS
ARG OCI_LICENSES
ARG OCI_VERSION
ARG OCI_REVISION

LABEL maintainer="Christian Rößner <christian@roessner.email>" \
      org.opencontainers.image.title="Postfix Alpine" \
      org.opencontainers.image.description="Postfix built from pinned source on Alpine Linux with dynamic map support, env-driven configuration, custom config overlays, and TLSRPT support" \
      org.opencontainers.image.licenses="${OCI_LICENSES}" \
      org.opencontainers.image.vendor="${OCI_VENDOR}" \
      org.opencontainers.image.authors="${OCI_AUTHORS}" \
      org.opencontainers.image.source="${OCI_SOURCE}" \
      org.opencontainers.image.url="${OCI_URL}" \
      org.opencontainers.image.documentation="${OCI_DOCUMENTATION}" \
      org.opencontainers.image.version="${OCI_VERSION}" \
      org.opencontainers.image.revision="${OCI_REVISION}" \
      org.opencontainers.image.base.name="docker.io/library/alpine:${ALPINE_VERSION}" \
      io.roessner.postfix.version="${POSTFIX_VERSION}" \
      io.roessner.postfix.tlsrpt.version="${TLSRPT_VERSION}" \
      io.roessner.postfix.tinycdb.version="${TINYCDB_VERSION}"

RUN apk upgrade --no-cache \
    && apk add --no-cache \
        ca-certificates \
        cyrus-sasl \
        cyrus-sasl-login \
        db \
        icu-libs \
        libmemcached-libs \
        libnsl \
        libpq \
        libtirpc \
        lmdb \
        mariadb-connector-c \
        mongo-c-driver \
        openldap \
        openssl \
        pcre2 \
        sqlite-libs \
    && addgroup -S postdrop \
    && addgroup -S postfix \
    && adduser -S -D -H -h /var/lib/postfix -s /sbin/nologin -G postfix postfix \
    && mkdir -p \
        /docker-entrypoint-init.d \
        /etc/postfix \
        /etc/postfix/custom-config/main.cf.d \
        /etc/postfix/custom-config/dynamicmaps.cf.d \
        /etc/postfix/custom-config/master.cf.d \
        /etc/postfix/maps \
        /usr/share/postfix/default-config \
        /var/lib/postfix \
        /var/spool/postfix

COPY --from=builder /tmp/out/ /
COPY --from=builder /usr/local/lib/libtlsrpt.so* /usr/local/lib/
COPY --from=builder /usr/local/lib/libcdb.so* /usr/local/lib/
COPY --from=builder /tmp/default-config/main.cf /usr/share/postfix/default-config/main.cf
COPY --from=builder /tmp/default-config/master.cf /usr/share/postfix/default-config/master.cf
COPY --from=builder /tmp/default-config/dynamicmaps.cf /usr/share/postfix/default-config/dynamicmaps.cf
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY docker-healthcheck.sh /usr/local/bin/docker-healthcheck.sh
COPY defaults/main.cf /usr/share/postfix/default-config/container-main.cf
COPY defaults/master.cf /usr/share/postfix/default-config/container-master.cf

RUN chmod 0755 /usr/local/bin/docker-entrypoint.sh /usr/local/bin/docker-healthcheck.sh \
    && chown -R root:root /etc/postfix /usr/share/postfix/default-config \
    && chown -R postfix:postfix /var/lib/postfix \
    && postconf -d smtputf8_enable | grep -q 'yes' \
    && (postfix set-permissions || true)

EXPOSE 25 465 587

HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=5 \
  CMD ["/usr/local/bin/docker-healthcheck.sh"]

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["postfix", "start-fg"]
