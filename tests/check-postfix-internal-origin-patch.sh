#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
postfix_version=$(sed -n 's/^ARG POSTFIX_VERSION=//p' "$repo_dir/Dockerfile")
external_patch="$repo_dir/patches/postfix-${postfix_version}-sasl-external-client-cert.patch"
origin_patch="$repo_dir/patches/postfix-${postfix_version}-internal-origin-upstream.patch"

check_sha()
{
    arg_name=$1
    patch_file=$2
    expected=$(sed -n "s/^ARG ${arg_name}=//p" "$repo_dir/Dockerfile")
    actual=$(sha256sum "$patch_file" | awk '{print $1}')
    if [ "$actual" != "$expected" ]; then
        echo "$patch_file checksum mismatch: expected $expected, got $actual" >&2
        exit 1
    fi
}

check_sha POSTFIX_INTERNAL_ORIGIN_PATCH_SHA256 "$origin_patch"

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/postfix-dsn-origin-source.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM

if [ "${POSTFIX_SOURCE_DIR:-}" ]; then
    cp -R "$POSTFIX_SOURCE_DIR" "$work_dir/postfix"
    source_dir="$work_dir/postfix"
else
    source_url=$(sed -n 's/^ARG POSTFIX_SOURCE_URL=//p' "$repo_dir/Dockerfile")
    source_url=$(printf '%s\n' "$source_url" | sed "s/\${POSTFIX_VERSION}/${postfix_version}/g")
    expected_source_sha=$(sed -n 's/^ARG POSTFIX_SHA256=//p' "$repo_dir/Dockerfile")
    curl -fsSLo "$work_dir/postfix.tgz" "$source_url"
    printf '%s  %s\n' "$expected_source_sha" "$work_dir/postfix.tgz" | sha256sum -c -
    tar -xzf "$work_dir/postfix.tgz" -C "$work_dir"
    source_dir="$work_dir/postfix-${postfix_version}"
fi

patch -d "$source_dir" -p1 < "$external_patch"
patch -d "$source_dir" -p1 < "$origin_patch"

test ! -e "$source_dir/conf/master.cf.rej"
if grep -Fq 'dsn_cleanup' "$source_dir/conf/master.cf"; then
    echo "unexpected separate dsn_cleanup service" >&2
    exit 1
fi
for origin in BOUNCE NOTIFY VERIFY; do
    grep -Fq "CLEANUP_FLAG_ORG_$origin" "$source_dir/src/global/cleanup_user.h"
done
grep -Fq '{postfix_internal_origin}' "$source_dir/src/cleanup/cleanup_milter.c"
grep -Fq '{postfix_internal_origin}' "$source_dir/src/global/mail_params.h"
grep -Fq 'cleanup_org_flag_from_source_flag(source_class)' "$source_dir/src/global/post_mail.c"
grep -Fq 'cleanup_org_flag_to_name(state->flags)' "$source_dir/src/cleanup/cleanup_milter.c"
grep -Fq 'cleanup_milter_origin_test' "$source_dir/src/cleanup/Makefile.in"
grep -Fq 'postfix-macros' "$source_dir/proto/MILTER_README.html"
if grep -R -E -q \
    'postfix_dsn_origin|CLEANUP_FLAG_DSN_ORIGIN|post_mail_fopen_dsn_nowait|postfix_dsn_evidence' \
    "$source_dir/src" "$source_dir/proto"; then
    echo "unexpected superseded downstream DSN interface" >&2
    exit 1
fi

echo "postfix upstream internal origin source contract: PASS"
