# Customized Postfix distribution

This image is maintained by Christian Roessner / Rößner-Network-Solutions.
It contains downstream Postfix modifications and is not an official Postfix
release or an assertion of endorsement by the upstream authors.

Postfix and our distributed modifications are provided under the IBM Public
License 1.0 (IPL-1.0). The upstream license file also offers EPL-2.0 for the
upstream software; this distribution uses IPL-1.0. Existing file-specific
licenses, copyright notices and acknowledgements remain applicable.

Copyright (c) 1997,1998,1999, International Business Machines Corporation
and others. All Rights Reserved.

Downstream contributions: Christian Roessner / Rößner-Network-Solutions,
2026: verified client-certificate SASL EXTERNAL bridge, CRL enforcement,
and mechanical backport of Wietse Venema's upstream internal-origin feature
from postfix-3.12-20260915. The original downstream DSN-origin implementation
has been removed. Upstream credits and semantics are preserved. See the README patch table and
the patch files for the changes. The MIT license for our independent
container tooling does not replace the Postfix license for these patches.

The complete modified Postfix source is available from us in every image at
`/usr/share/doc/postfix-custom/sources/build-sources.tar.gz`, together with
the sources of libtlsrpt and tinycdb compiled into that image, original
license notices, the build recipe and patches. The adjacent SHA256SUMS file
identifies the archive. Extraction instructions are in README.md. The full
Postfix license is at `/usr/share/doc/postfix-custom/licenses/POSTFIX-LICENSE`.

The software is provided without warranty under the applicable licenses.
No additional warranty, support or liability is offered on behalf of IBM,
Wietse Venema or any other upstream contributor. Consult the accompanying
license texts for the full warranty exclusions and limitations of liability.

libtlsrpt, tinycdb and Alpine runtime packages retain their own licenses.
The OCI license label is an overview of principal components, not an
exhaustive replacement for package-specific notices and source obligations.
