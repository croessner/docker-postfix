#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
patch_file="$repo_dir/patches/postfix-3.11.5-sasl-external-client-cert.patch"
expected_patch_sha=$(sed -n 's/^ARG POSTFIX_EXTERNAL_PATCH_SHA256=//p' "$repo_dir/Dockerfile")
actual_patch_sha=$(sha256sum "$patch_file" | awk '{print $1}')

if [ "$actual_patch_sha" != "$expected_patch_sha" ]; then
    echo "patch checksum mismatch: expected $expected_patch_sha, got $actual_patch_sha" >&2
    exit 1
fi

if [ "${POSTFIX_SOURCE_DIR:-}" ]; then
    source_dir=$POSTFIX_SOURCE_DIR
    cleanup=false
else
    work_dir=$(mktemp -d "${TMPDIR:-/tmp}/postfix-external-source.XXXXXX")
    cleanup=true
    trap 'if $cleanup; then rm -rf "$work_dir"; fi' EXIT HUP INT TERM
    source_url=$(sed -n 's/^ARG POSTFIX_SOURCE_URL=//p' "$repo_dir/Dockerfile")
    source_url=$(printf '%s\n' "$source_url" | sed 's/${POSTFIX_VERSION}/3.11.5/g')
    expected_source_sha=$(sed -n 's/^ARG POSTFIX_SHA256=//p' "$repo_dir/Dockerfile")
    curl -fsSLo "$work_dir/postfix.tgz" "$source_url"
    printf '%s  %s\n' "$expected_source_sha" "$work_dir/postfix.tgz" | sha256sum -c -
    tar -xzf "$work_dir/postfix.tgz" -C "$work_dir"
    source_dir="$work_dir/postfix-3.11.5"
fi

patch -d "$source_dir" -p1 --dry-run < "$patch_file"

grep -Fq 'ssl_client_verify=SUCCESS' "$patch_file"
grep -Fq 'ssl_client_san_email=%s' "$patch_file"
grep -Fq 'ssl_client_fingerprint=%s' "$patch_file"
grep -Fq 'X509_V_FLAG_CRL_CHECK_ALL' "$patch_file"
grep -Fq 'SSL_CTX_set_num_tickets(server_ctx, 0)' "$patch_file"
grep -Fq 'SSL_CTX_set_num_tickets(sni_ctx, 0)' "$patch_file"
grep -Fq 'SSL_CTX_set_session_cache_mode(server_ctx, SSL_SESS_CACHE_OFF)' "$patch_file"
grep -Fq 'SSL_CTX_set_session_cache_mode(sni_ctx, SSL_SESS_CACHE_OFF)' "$patch_file"
grep -Fq 'no SASL authentication mechanisms available for %s' "$patch_file"
grep -Fq 'leaves no SASL authentication mechanisms available for %s' "$patch_file"
if grep -Eq '^\+.*msg_fatal\("%s discards all mechanisms' "$patch_file"; then
    echo "static SASL filter exhaustion must not terminate smtpd" >&2
    exit 1
fi
grep -Fq 'smtpd_sasl_deactivate(state);' "$patch_file"
grep -Fq 'TLS_ATTR_PEER_RFC822NAME' "$patch_file"
grep -Fq 'ret == 26' "$patch_file"
grep -Fq 'ret == 21' "$patch_file"
grep -Fq 'tls_external: PASS' "$patch_file"

echo "postfix external patch source contract: PASS"
