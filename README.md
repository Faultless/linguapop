# LinguaPop

A Japanese language-learning novel reader. Import an EPUB/TXT (or a paired original + translation) and
read with per-token JLPT color coding, tap-for-dictionary, select-for-translation, switchable view
modes, custom themes and TTS — fully offline. Flutter → **Android, web and Linux desktop** from one
codebase (iOS scaffolds with `flutter create . --platforms ios`).

## Get started

```bash
git clone https://github.com/Faultless/linguapop.git
cd linguapop-extension
flutter pub get
flutter run                      # run on any connected device
```

## Build for your platform

```bash
flutter build apk --release      # Android
flutter build web                # web (tokenizer is degraded — no native MeCab)
flutter build linux              # Linux desktop
```

## Checks

```bash
flutter analyze
flutter test
```

For architecture, conventions and the TS→Flutter port status, see `CLAUDE.md`.

## Licence

LinguaPop is free software under the **GNU General Public License v3.0 or
later** — see [`LICENSE`](LICENSE).

Bundled third-party components keep their own licences:

- **MeCab** (vendored at `plugins/mecab_dart/`) — GPL / LGPL / BSD, at your
  option; see `plugins/mecab_dart/COPYING.mecab`.
- **IPADIC** (`assets/ipadic/`) — a permissive BSD-style licence from the Nara
  Institute of Science and Technology; see `assets/ipadic/COPYING`.
- **JLPT vocabulary lists** (`assets/jlpt/`) — the open Tanos / Jonathan Waller
  lists.

## F-Droid

`fdroid/com.linguapop.linguapop.yml` is the build recipe submitted to
[fdroiddata](https://gitlab.com/fdroid/fdroiddata). Keep it in step with the
app when the Flutter version (`FLUTTER_VERSION`), the NDK version
(`android/app/build.gradle.kts`) or the release tag changes —
`test/fdroid_metadata_test.dart` fails if it drifts, which is cheaper than
waiting an hour for F-Droid's buildserver to say so.

F-Droid signs with its own key, so its build deletes the line marked
`FDROID-STRIP` in `android/app/build.gradle.kts` during prebuild. Nothing else
in that file may carry the marker — a test enforces it.

Release builds sign with a real keystore when `android/key.properties` exists
(`storeFile` / `storePassword` / `keyAlias` / `keyPassword`), and fall back to
the debug key when it doesn't. That file and the keystore are gitignored. **If
you create one, back it up** — losing it means never being able to ship an
update that existing installs will accept.

### Cutting a release

Release APKs are built by the **Release APKs** GitHub Actions workflow on
linux-x86_64, not locally. F-Droid rebuilds each tagged commit and compares it
against the binary published here, and only a Linux x86_64 build stands a
chance of matching — a macOS build differs in `libapp.so`, the two
NDK-compiled `.so`s and `NOTICES.Z`, and Flutter ships no linux-arm64 host
`gen_snapshot` for Android AOT at all, so a container on an Apple Silicon
machine can't stand in either. The workflow also mirrors F-Droid's absolute
build paths, because package URIs and source paths are baked into those
binaries.

    gh workflow run "Release APKs" -f ref=v7.4.1     # build
    tool/sign_release.sh <run-id> 7.4.1              # sign locally, publish

The workflow produces **unsigned** APKs on purpose — the signing key stays off
CI. `apksigner` only adds a signing block and leaves every zip entry untouched,
which is the part F-Droid compares; `tool/sign_release.sh` asserts that.

    tool/check_reproducible.py fdroid-build.apk our-release.apk

compares two APKs the way F-Droid's verification does and names the entries
that diverge. F-Droid's own build artifacts can be pulled from the merge
request's `fdroid build` job, which makes it possible to check reproducibility
locally instead of a round trip through their CI.

One APK per ABI, with version codes `buildNumber * 10 + abi`
(armeabi-v7a=1, arm64-v8a=2, x86_64=3), applied in `android/app/build.gradle.kts`
because Flutter's own scheme puts the ABI in the high digits and leaves no room
to grow. Store listing text lives in `fastlane/metadata/android/en-US/`.
