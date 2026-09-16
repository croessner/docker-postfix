# Upstream internal-origin backport

Image revision: 3.11.7-r1. Base: official Postfix 3.11.7.

## Source and scope

Wietse Venema announced the integrated implementation on 2026-09-15:
https://www.mail-archive.com/postfix-devel@postfix.org/msg01355.html

Authoritative source archive:
http://ftp.porcupine.org/mirrors/postfix-release/experimental/postfix-3.12-20260915.tar.gz

SHA-256: `b72082fcbaf36dae65ce7220e619200c50171920810a36ab79defa94ff8068fa`.

Stable base archive SHA-256:
`a2f3242345753448072177fae83c322a403c9263696996406201145dab8e8625`.
Re-downloaded and checked on 2026-09-16: this stable archive contains no
`postfix_internal_origin` feature. The earlier 2026-09-11 mail described patch
applicability to 3.11, not inclusion in stable 3.11.7.

The patch extracts only the final provenance feature: cleanup origin bits and
mapping, post_mail source-class propagation, Milter evaluation/default macro,
upstream origin regression fixtures, author credit and feature documentation.
Unrelated 3.12 TLS, parser, test-framework and configuration changes are excluded.
Build-list/context adaptations integrate those exact upstream feature blocks
with the stable 3.11.7 layout. The patch header records the extraction details.
Upstream documentation's “Postfix >= 3.12” wording remains intact: availability
on 3.11.7-r1 is specific to this explicitly identified backport.

The separate SASL EXTERNAL / CRL patch is unchanged. The two old downstream
DSN-origin patches and their special bounce-posting function are removed.
No alias from the new macro to the old macro is provided.

## Acceptance and coordinated deployment

- Source application and checksums; absence of the superseded interface.
- Compiled upstream cleanup regression suite, including origin fixtures.
- Existing TLS EXTERNAL and bounce regression suites.
- Runtime default-macro/readback and embedded-source checks.
- Matching DKIM2 adapter: exact upstream enum, transaction-bound provenance;
  non-null double-bounces, notify, verify and unmarked mail remain outside the
  normal DSN signing route.
- Mailstack: pause affected message processing for the coordinated image,
  adapter and explicit macro-list replacement; retain the entire old tuple
  for rollback, then prove a local DSN and an external null-sender negative case.
- dkim2pub has no Postfix Milter endpoint; refresh its daemon digest only after
  verifying unchanged HTTP/OpenAPI contracts and normal validation behavior.

This document identifies the backport and acceptance criteria. Live rollout
results belong to each deployment owner's dated report.
