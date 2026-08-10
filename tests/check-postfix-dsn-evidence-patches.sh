#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
postfix_version=$(sed -n 's/^ARG POSTFIX_VERSION=//p' "$repo_dir/Dockerfile")
external_patch="$repo_dir/patches/postfix-${postfix_version}-sasl-external-client-cert.patch"
patch_0001="$repo_dir/patches/postfix-${postfix_version}-dsn-evidence-0001.patch"
patch_0002="$repo_dir/patches/postfix-${postfix_version}-dsn-evidence-0002.patch"

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

check_sha POSTFIX_DSN_EVIDENCE_PATCH_0001_SHA256 "$patch_0001"
check_sha POSTFIX_DSN_EVIDENCE_PATCH_0002_SHA256 "$patch_0002"

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/postfix-dsn-evidence-source.XXXXXX")
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
patch -d "$source_dir" -p1 < "$patch_0001"
patch -d "$source_dir" -p1 < "$patch_0002"

test ! -e "$source_dir/conf/master.cf.rej"
if grep -Fq 'dsn_cleanup' "$source_dir/conf/master.cf"; then
    echo "unexpected separate dsn_cleanup service" >&2
    exit 1
fi
grep -Fq 'CLEANUP_FLAG_DSN_ORIGIN' "$source_dir/src/global/cleanup_user.h"
grep -Fq 'MAIL_ATTR_DSN_ORIG_ENVELOPE' "$source_dir/src/global/mail_proto.h"
grep -Fq '{postfix_dsn_evidence}' "$source_dir/src/cleanup/cleanup_milter.c"
grep -Fq 'postfix-dsn-evidence-v1' "$source_dir/src/cleanup/cleanup_milter.c"
grep -Fq '{postfix_dsn_original_envelope}' "$source_dir/src/cleanup/cleanup_milter.c"
grep -Fq 'post_mail_fopen_dsn_nowait' "$source_dir/src/bounce/bounce_notify_util.c"
grep -Fq 'var_cleanup_service' "$source_dir/src/global/post_mail.c"
grep -Fq 'Local-MTA evidence for delivery status notifications' \
    "$source_dir/proto/MILTER_README.html"
if grep -Fq '{postfix_dsn_original_queue_id}' \
    "$source_dir/src/cleanup/cleanup_milter.c"; then
    echo "unexpected original queue ID macro" >&2
    exit 1
fi

echo "postfix dsn evidence patch series source contract: PASS"
