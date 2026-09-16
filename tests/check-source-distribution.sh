#!/bin/sh
set -eu

# Run inside the built image. Verify that the sources actually shipped with
# the binary contain our interfaces and can be traced to the installed version.
cd /usr/share/doc/postfix-custom/sources
sha256sum -c SHA256SUMS
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
tar -xzf build-sources.tar.gz -C "$work_dir"
version=$(postconf -h mail_version)
grep -Fx "Postfix=$version" "$work_dir/source-recipe/BUILD-SOURCES.txt"
grep -Fq 'CLEANUP_FLAG_ORG_BOUNCE' "$work_dir/postfix/src/global/cleanup_user.h"
grep -Fq 'postfix_internal_origin' "$work_dir/postfix/src/cleanup/cleanup_milter.c"
grep -Fq 'ssl_client_san_email' "$work_dir/postfix/src/xsasl/xsasl_dovecot_server.c"
test -s "$work_dir/postfix/LICENSE"
test -s "$work_dir/source-recipe/NOTICE.md"
test -s "$work_dir/source-recipe/Dockerfile"
test -s "$work_dir/tinycdb/Makefile"
test -s "$work_dir/libtlsrpt/configure.ac"
cmp "$work_dir/postfix/LICENSE" /usr/share/doc/postfix-custom/licenses/POSTFIX-LICENSE
echo 'embedded source distribution: PASS'
