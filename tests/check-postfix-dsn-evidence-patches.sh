#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
external_patch="$repo_dir/patches/postfix-3.11.5-sasl-external-client-cert.patch"
patch_0001="$repo_dir/patches/postfix-3.11.5-dsn-evidence-0001.patch"
patch_0002="$repo_dir/patches/postfix-3.11.5-dsn-evidence-0002.patch"
patch_0003="$repo_dir/patches/postfix-3.11.5-dsn-evidence-0003.patch"

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
check_sha POSTFIX_DSN_EVIDENCE_PATCH_0003_SHA256 "$patch_0003"

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/postfix-dsn-evidence-source.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM

if [ "${POSTFIX_SOURCE_DIR:-}" ]; then
    cp -R "$POSTFIX_SOURCE_DIR" "$work_dir/postfix"
    source_dir="$work_dir/postfix"
else
    source_url=$(sed -n 's/^ARG POSTFIX_SOURCE_URL=//p' "$repo_dir/Dockerfile")
    source_url=$(printf '%s\n' "$source_url" | sed 's/${POSTFIX_VERSION}/3.11.5/g')
    expected_source_sha=$(sed -n 's/^ARG POSTFIX_SHA256=//p' "$repo_dir/Dockerfile")
    curl -fsSLo "$work_dir/postfix.tgz" "$source_url"
    printf '%s  %s\n' "$expected_source_sha" "$work_dir/postfix.tgz" | sha256sum -c -
    tar -xzf "$work_dir/postfix.tgz" -C "$work_dir"
    source_dir="$work_dir/postfix-3.11.5"
fi

patch -d "$source_dir" -p1 < "$external_patch"
patch -d "$source_dir" -p1 < "$patch_0001"
patch -d "$source_dir" -p1 < "$patch_0002"
patch -d "$source_dir" -p1 < "$patch_0003"

test ! -e "$source_dir/conf/master.cf.rej"
grep -Fq 'dsn_cleanup unix y' "$source_dir/conf/master.cf"
grep -Fq 'MAIL_SERVICE_DSN_CLEANUP' "$source_dir/src/global/mail_proto.h"
grep -Fq '{postfix_dsn_evidence}' "$source_dir/src/cleanup/cleanup_milter.c"
grep -Fq 'postfix-dsn-evidence-v1' "$source_dir/src/cleanup/cleanup_milter.c"
grep -Fq '{postfix_dsn_original_queue_id}' "$source_dir/src/cleanup/cleanup_milter.c"
grep -Fq '{postfix_dsn_original_envelope}' "$source_dir/src/cleanup/cleanup_milter.c"
grep -Fq 'post_mail_fopen_dsn_nowait' "$source_dir/src/bounce/bounce_notify_util.c"

echo "postfix dsn evidence patch series source contract: PASS"
