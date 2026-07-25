# LinguaPop

A Japanese language-learning novel reader. Import an EPUB/TXT (or a paired original + translation) and
read with per-token JLPT color coding, tap-for-dictionary, select-for-translation, switchable view
modes, custom themes and TTS — fully offline. Flutter → **Android, web and Linux desktop** from one
codebase (iOS scaffolds with `flutter create . --platforms ios`).

## Get started

```bash
git clone https://github.com/Faultless/linguapop-extension.git
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
