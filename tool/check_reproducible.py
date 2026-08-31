#!/usr/bin/env python3
"""Compare two APKs the way F-Droid's verification does.

F-Droid rebuilds a tagged commit and checks its output against the binary the
developer published. Signatures are expected to differ; nothing else may. So
this compares every zip entry except the JAR signature files, and reports
exactly which ones diverge.

Two uses:

    # Does our published binary match F-Droid's build of the same commit?
    tool/check_reproducible.py fdroid-build.apk our-release.apk

    # Did signing disturb anything it shouldn't have?
    tool/check_reproducible.py --signing-only unsigned.apk signed.apk

Exits non-zero when they differ, so it can gate a release.

Known-difficult entries, for context when something does differ:
  lib/*/libapp.so         the Dart AOT snapshot — embeds package URIs, so
                          PUB_CACHE and the source path must match
  lib/*/libdartjni.so     NDK-compiled; embeds source/toolchain paths
  lib/*/libmecab_dart.so  ditto, the vendored MeCab
  assets/.../NOTICES.Z    generated and gzipped by the Flutter asset bundler;
                          differs across host platforms
"""

import argparse
import hashlib
import sys
import zipfile

# JAR signature files. The v2/v3 signature lives in the APK Signing Block,
# which isn't a zip entry at all, so it never shows up here.
SIGNATURE_SUFFIXES = ('RSA', 'SF', 'MF', 'DSA', 'EC')


def is_signature(name: str) -> bool:
    if not name.startswith('META-INF/'):
        return False
    return name.rsplit('.', 1)[-1].upper() in SIGNATURE_SUFFIXES


# Compared alongside content, because the v2/v3 signature digests cover the
# whole file: two APKs whose entries all match can still fail verification if
# the container differs. `header_offset` is the one that actually bit me —
# apksigner realigns by default, shifting every entry a few bytes.
CONTAINER_FIELDS = (
    'date_time', 'compress_type', 'CRC', 'compress_size', 'file_size',
    'flag_bits', 'header_offset',
)


def entries(path: str) -> dict[str, tuple]:
    with zipfile.ZipFile(path) as z:
        out = {}
        for n in z.namelist():
            if n == 'META-INF/' or is_signature(n):
                continue
            i = z.getinfo(n)
            out[n] = (
                hashlib.sha256(z.read(n)).hexdigest(),
                tuple(getattr(i, f) for f in CONTAINER_FIELDS),
                len(i.extra),
            )
        return out


def order(path: str) -> list[str]:
    with zipfile.ZipFile(path) as z:
        return [n for n in z.namelist() if not is_signature(n)]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('reference', help='APK to compare against')
    ap.add_argument('candidate', help='APK under test')
    ap.add_argument(
        '--signing-only',
        action='store_true',
        help='the two differ only by signing; any content change is a failure',
    )
    args = ap.parse_args()

    a = entries(args.reference)
    b = entries(args.candidate)

    only_a = sorted(set(a) - set(b))
    only_b = sorted(set(b) - set(a))
    changed = sorted(n for n in set(a) & set(b) if a[n] != b[n])
    reordered = order(args.reference) != order(args.candidate)

    if reordered:
        print('DIFFERS: entry order is not the same')
        return 1

    if not (only_a or only_b or changed):
        what = 'signing left every entry and offset untouched' \
            if args.signing_only else f'{len(a)} entries identical, container too'
        print(f'OK: {what}')
        return 0

    print(f'DIFFERS  reference={len(a)} entries  candidate={len(b)} entries')
    for n in only_a:
        print(f'  only in reference: {n}')
    for n in only_b:
        print(f'  only in candidate: {n}')
    for n in changed:
        note = ''
        if a[n][0] == b[n][0]:
            note = '  (contents match; the container differs — offsets or ' \
                   'timestamps. Signing without --alignment-preserved does this)'
        elif n.endswith('libapp.so'):
            note = '  (Dart AOT snapshot — check PUB_CACHE and source path)'
        elif n.endswith('.so'):
            note = '  (NDK output — check source and toolchain paths)'
        elif n.endswith('NOTICES.Z'):
            note = '  (asset bundler — check host platform)'
        print(f'  content differs: {n}{note}')
    return 1


if __name__ == '__main__':
    sys.exit(main())
