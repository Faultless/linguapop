# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

LinguaPop is a Japanese language-learning novel reader. Users import EPUB/TXT files (or a paired original+translation), and read them with switchable view modes (original / translated / parallel), per-token JLPT color coding for Japanese, tap-for-dictionary, select-for-translation, custom themes, multiple layouts, TTS, and fullscreen.

**This is a Flutter port.** The repo was previously a React/TypeScript monorepo (extension + web + mobile + landing); that code now lives in `legacy_ts/` and is kept only as a reference during the port. It is **not** built or shipped.

## Targets

Single Flutter codebase, three runtime targets:

- **Android** — primary target. Native back-button navigation, edge-to-edge system bars, MeCab tokenizer bundled natively.
- **Linux desktop** — same code, runs as a native desktop app.
- **Web** — Flutter web build. MeCab is unavailable here; the tokenizer falls back to a degraded mode (planned).

No iOS scaffold (can be added later with `flutter create . --platforms ios`).

## Project structure

```
lib/
  main.dart                 — bootstrap: Hive init, edge-to-edge, ProviderScope
  app.dart                  — root MaterialApp.router, reads activeThemeProvider
  data/
    models/                 — Chapter, NovelMeta, NovelBody, ReaderPrefs, ReaderTheme,
                              VocabEntry, DictEntry/Sense/Result, JlptStats, JpToken
    storage/storage.dart    — Hive box registration (prefs / novels_meta / novel_body /
                              jpdict / vocab); see "Storage layout" below
    themes/builtin_themes.dart — 11 BUILTIN_THEMES (paper/sepia/cream/rose/mint/
                              night/midnight/forest/eink/highc/burnout +
                              sakura/momiji/matcha/ai/sumi), JLPT color map
  providers/                — Riverpod state notifiers
    prefs_provider.dart     — readerPrefsProvider, activeThemeProvider
    novels_provider.dart    — novelsProvider (meta list), novelBodyProvider (family)
    vocab_provider.dart     — vocabProvider
  ui/
    router.dart             — go_router config; routes nested under /
    screens/                — library, reader, settings, import, vocab,
                              sources, news (newspaper front page)
    widgets/                — NovelCard/NovelListRow/NovelWideCard, JapaneseText,
                              JlptBadge, DifficultyBadge, NewsThumb (lazy image),
                              ViewModeButton, MiniToast,
                              newspaper.dart (masthead / rules / PaperTab),
                              front_page.dart (FrontPageBand masonry)

legacy_ts/                  — old React/TS monorepo, reference only
assets/jlpt/                — JLPT vocab JSON (to be generated from legacy data)
```

## Common Commands

```bash
flutter pub get                # install Dart deps
flutter run                    # run on connected Android device / desktop / web
flutter run -d chrome          # web
flutter run -d linux           # Linux desktop
flutter analyze                # static analysis (lints + type check)
flutter test                   # run tests
flutter build apk --debug      # Android debug APK
flutter build apk --release    # Android release APK
flutter build web              # web build to build/web/
flutter build linux            # Linux desktop build
```

## Architecture

### State management

Riverpod (`flutter_riverpod`). One `StateNotifier` per persistent domain:

- `ReaderPrefsNotifier` — every reader pref, serializes to `Storage.prefs()['reader_prefs']` as JSON.
- `NovelsNotifier` — library `NovelMeta[]` list, plus body load/save methods. Bodies are stored per-id in `Storage.novelBody()` so the meta list stays small.
- `VocabNotifier` — flat `VocabEntry[]`, dedup keyed on `(base, isPhrase)`.

`activeThemeProvider` derives the current `ReaderTheme` from `readerPrefsProvider`. `MaterialApp.router` consumes it so theme changes propagate instantly.

### Storage layout (Hive)

| Box           | Key                  | Value                              |
|---------------|----------------------|------------------------------------|
| `prefs`       | `reader_prefs`       | JSON-encoded `ReaderPrefs`         |
| `novels_meta` | `list`               | JSON list of `NovelMeta`           |
| `novel_body`  | `{novelId}`          | JSON `NovelBody`                   |
| `jpdict`      | `{query}`            | JSON `DictResult` (infinite cache) |
| `vocab`       | `list`               | JSON list of `VocabEntry`          |
| `covers`      | `{novelId}`          | base64-encoded local cover image bytes |

The `prefs` box also holds key `collections` (JSON list of `Collection`) for user-defined library shelves.

Logical equivalents of the legacy JS localStorage/IndexedDB layout — same JSON shape so future migration tooling is straightforward.

### Navigation

`go_router` with all routes nested under `/`. Android system back button works out of the box — `MaterialApp.router` wires up the Navigator pop chain. Routes:

- `/` — Library
- `/book/:novelId` — Book detail (cover/rating-less metadata edit, collections, tags, cover picker)
- `/reader/:novelId` — Reader (`?ch=N` query param deep-links to a chapter, used by the news hub)
- `/news` — Front page (newspaper layout over all imported feed articles). `?paper=<sourceId>` opens one paper; `all` is every paper.
- `/reader/:novelId/settings` — Reader settings (also `/settings`)
- `/import` — File-picker import flow (stub)
- `/vocab` — Saved vocab list
- `/sources` — Browse + import from online sources
- `/sources/manage` — Which papers the newsstand carries

### Settings

`lib/ui/screens/settings_screen.dart` is a hub, not a scroll: `ReaderSettingsScreen` lists one row per area (Theme, Text & layout, Japanese, Papers, and — outside reading mode — Saved vocabulary and Browse sources), each with a live subtitle showing the current value. The leaves (`ThemeSettingsScreen`, `TextSettingsScreen`, `JapaneseSettingsScreen`, `SourceManagerScreen`) are pushed onto the ambient Navigator rather than routed — nothing deep-links to them, and it keeps `/settings` and `/reader/:id/settings` from each needing a parallel set of child routes. The reading-mode switch sits at the top of the hub in both modes.

### App icon

`tool/make_icon.py` owns the mark: the kanji 言 drawn as pure geometry — a short top stroke, three bars, and an open box — which reads at once as the character and as newsprint columns over a headline box. One geometry spec emits `assets/icon/linguapop.svg`, the Android adaptive-icon `VectorDrawable`s (foreground + an Android 13 monochrome layer), and the legacy `mipmap-*/ic_launcher.png` raster set for API < 26. There's no image library or SVG rasteriser assumed on the machine, so the PNGs are rendered with analytic per-pixel rectangle coverage through a ~40-line PNG encoder. Re-run `python3 tool/make_icon.py` after editing the spec; don't hand-edit the generated files.

### Theming

`ReaderTheme.toThemeData()` produces a Material 3 `ThemeData` seeded from the theme's accent color and overriding `surface`/`onSurface` with the theme's bg/fg. App-wide theme is whatever the user picked in `prefs.themeId`. AppBar / BottomSheet / Card / ListTile inherit through standard Material theming — no per-widget inline colors needed.

### List view modes

Library and news screens share a `LibraryViewMode { grid, list, card }` (persisted in `ReaderPrefs.libraryViewMode` / `newsViewMode`), toggled via `ViewModeButton` in each app bar:
- **grid** ("Media") — cover/image-forward tiles. Library shows `NovelCard` (cover + clamped 2-line title + author; tags intentionally omitted here to avoid grid-cell overflow). News shows 16:9 image cards.
- **list** — compact rows. `NovelListRow` (46px cover thumb + title/author/clamped tag row) and the news `_ArticleRow` (title + source·time + difficulty bar + small lead thumb).
- **card** ("Cards") — full-width rich cards. `NovelWideCard` (64px cover + title + author + tag wrap + progress) and a taller news row with a 2-line snippet and an 84px image.

All entry widgets clamp text with `maxLines`+ellipsis and wrap variable rows (title beside badges, source/time beside difficulty) in `Expanded`/`Flexible`, so long titles or tag lists can't overflow. Tag rows clamp to a fixed count with a `+N` indicator.

News lead images (`Chapter.imageUrl`) are lazy: `NewsThumb` uses `Image.network` (streamed + ImageCache-backed) with a `cacheWidth` cap and fade-in, falling back silently to a glyph on error/no-image, so images never block list scrolling. `imageUrl` is captured at import time — from each adapter's article `og:image` (`ogImage()` in `rss.dart`), falling back to the feed stub's image; threaded through `SourceImporter.importArticle`.

### Transient feedback

`MiniToast.show(context, msg)` (`lib/ui/widgets/mini_toast.dart`) is a tiny bottom-left overlay toast that fades in/out almost instantly (~90ms in, ~650ms hold, ~180ms out) and replaces itself in place. Used for low-importance confirmations in the sources browser ("Adding…", "Added ✓", "Removed") instead of full-width SnackBars. Failures still use a SnackBar so they're dismissible and visible.

### Library organization

Kindle-style classification on top of `NovelMeta`:
- **Cover art**: `lib/services/covers/cover_service.dart` queries the Google Books Volumes API (no key, `package:http` so it works on web too — unlike the `dart:io` `SessionClient`). `NovelsNotifier.autoFetchCover(id)` runs best-effort on import for books with no embedded cover. The book detail screen's cover picker also offers online search, paste-URL, and pick-from-device. Device-picked images are stored as base64 in the `covers` box and referenced by a `local:{novelId}` `coverUrl`; `BookCover` renders the three cases (`local:` → `Image.memory`, remote/`data:` → `Image.network`, none → procedural) and watches `coverRevisionProvider` so a freshly-picked cover repaints.
- **Collections**: user-named shelves. `Collection` model + `collectionsProvider` (persisted in the `prefs` box under `collections`). Books reference them by id via `NovelMeta.collectionIds`, so renaming never rewrites the meta list. Library has a Collection filter chip.
- **Favorites**: `NovelMeta.favorite` (heart toggle in detail + a Favorites filter chip; heart overlay on the grid card).
- **Continue reading**: `NovelMeta.lastReadAt` (bumped by the reader's progress save) drives a horizontal "Continue reading" row at the top of the library, showing in-progress books most-recently-read first. Hidden when any filter is active.
- **Book detail screen**: `lib/ui/screens/book_detail_screen.dart` (`/book/:novelId`, opened by long-pressing a library card) hosts cover editing, favorite, collections, tags, content type, and remove.

### Japanese pipeline

- **Tokenizer**: `lib/services/tokenizer/` — abstract `JpTokenizer` with a conditional-import factory:
  - `mecab_tokenizer_native.dart` — wraps the vendored `plugins/mecab_dart` FFI plugin, bundles IPADIC from `assets/ipadic/` (~51 MB, copied to documents dir on first run), maps MeCab features to our `JpToken` model (base form, hiragana reading, POS, 活用型/活用形, filler flag).
  - `conjugation_merger.dart` — post-pass over the raw morphemes: merges verb/adjective stems with their auxiliary chain (て-connectors, 助動詞, 非自立 helper verbs, 接尾 voice suffixes) into one token per conjugated phrase, with a `ConjugationInfo` (form labels like progressive/polite/past/passive/causative + per-morpheme breakdown). Merged surfaces always concatenate back to the original text. Unit-tested against known IPADIC analyses in `test/conjugation_merger_test.dart`.

    Three kinds of phrase head (`_HeadKind`): plain 動詞,自立 / 形容詞,自立; **suru-verbs** (名詞,サ変接続 + する → 発表しました as one token with base 発表する and verb POS); and **na-adjectives** (名詞,形容動詞語幹 + だ/です → 静かでした with base 静か and adjective POS). Beyond the auxiliary chain it also absorbs the multi-morpheme grammar patterns MeCab splits across clause boundaries: 〜なければならない (obligation), 〜てはいけない (prohibition), 〜てもいい (permission), plus the ながら / たり / つつ / し / と connectors. The copula is distinguished from the past marker by 活用型 (特殊・ダ vs 特殊・タ), so 読んだ is "past" while 静かだった's だ is just a part.
  - `mecab_tokenizer_stub.dart` — web fallback (returns the whole text as one filler token).
- **JLPT lookup**: `lib/services/dictionary/jlpt_lookup.dart`. Loads two bundled JSON assets at app start:
  - `assets/jlpt/vocab.json` — 8,034 entries from the open Tanos / Jonathan Waller list.
  - `assets/jlpt/starter.json` — 307 curated common keys (particles, kana words) keyed by comma-separated surfaces.
  Both are merged into a single `String → JlptHit` map. Duplicate keys keep the easier level. The `register()` method lets cached Jisho lookups merge in later.

  8k words covers only a fraction of real news prose, so there are two fallback layers on top of the exact map:
  1. **De-inflection** (`lookup`) — 五段 potential (読める → 読む), passive/causative bases (見られる → 見る), suru-verb bases from the merger (発表する → 発表), and productive affixes (経済的 → 経済, ご案内 → 案内). Still an exact hit when it lands.
  2. **Estimation** (`estimate`) — a word with no listed form is scored from the JLPT levels of its individual kanji. The kanji→level table is derived from the bundled vocabulary itself at load time (each kanji keeps the *easiest* level it appears at); a word's estimate is its *hardest* kanji, since that's what a reader stumbles on. Unlisted katakana of 3+ characters is guessed at N2. Results carry `JlptHit.approximate`, rendered with a dashed underline and a `~N3` badge so an estimate never passes for a listing.

  `ReaderPrefs.highlightUnlisted` (default on, toggled in reader settings) gates layer 2. `JapaneseText._estimable` keeps numbers, counters, bound nouns and pronouns out of it — colouring those buries the words that matter. Tested against the real assets in `test/jlpt_lookup_test.dart`.
- **JapaneseText widget**: `lib/ui/widgets/japanese_text.dart`. While the tokenizer is loading the text renders plain; once `tokenizerStatusProvider` flips to `ready` it retokenizes and renders each content token as a colored `TextSpan` — dotted underline for a listed level, dashed for an estimated one. Respects `prefs.coloriseJapanese`, `prefs.highlightUnlisted`, and the `prefs.jlptColorRules` POS×level matrix.
- **JLPT colors**: N5=teal, N4=green, N3=amber, N2=orange, N1=red (see `kJlptColors`).
- **Warm-up**: `LinguapopApp` reads `tokenizerStatusProvider.future` + `jlptLoadedProvider.future` in a post-frame callback so the first chapter open isn't blocked on a 51 MB asset copy.

**Native build notes** (Android, see `plugins/mecab_dart/`):
- The vendored plugin keeps the upstream FFI Dart side (`lib/mecab_dart.dart`) unchanged so future upstream merges stay easy. Only the Android Kotlin plugin (V1 → V2 embedding) and `build.gradle` (AGP 7.3 → 8.7, Kotlin 1.7 → 2.0, minSdk 21, namespace) were updated.
- MeCab's C++ uses `register` storage class, removed in C++17. `plugins/mecab_dart/android/CMakeLists.txt` pins to C++14 and adds `-Wno-register` so it builds against the modern NDK.

### Dictionary popover

- **Service**: `lib/services/dictionary/jisho_service.dart`. Calls Jisho's public JMdict-derived API, caches every successful query in the `jpdict` Hive box forever (offline fallback to cache on subsequent network failures), and feeds JLPT-tagged hits back into the in-memory `JlptLookup` via `register()` so previously-tapped words light up on the next read.
- **UI**: `lib/ui/widgets/word_popover.dart` — `showWordPopover()` opens a draggable bottom sheet with the headword, reading, base form, conjugation analysis for merged verb phrases (form-label chips + morpheme breakdown, e.g. 食べ + て + い + まし + た), every Jisho sense (parts of speech + glosses), JLPT badge, "common" badge, and a "Save to vocab" action that writes a `VocabEntry` attributed to the current novel + chapter.
- The reader's `JapaneseText` wires every colored token's `onTapToken` callback to this popover.

### Importers

`lib/services/import/` contains the ported flow:
- `epub_importer.dart` — `parseEpub(Uint8List)`. ZIP via `archive`, OPF/XHTML via `xml`. Pulls metadata (title, author, language, cover data URL), walks the spine, extracts visible text with block-level newline insertion. Falls back to a regex tag strip if XHTML is malformed.
- `txt_importer.dart` — `splitTxtIntoChapters(text)`. Same heuristic as the legacy (chapter regex → markdown headings → `---`/`***` → 3+ blank lines), single-chapter fallback.
- `novel_cleaner.dart` — `pruneNovel()` and `alignChapters()`.
- `jp_detect.dart` — `looksJapanese()`.
- `import_service.dart` — `ImportService.importFile()` orchestrates the whole flow (parse → prune → optional align → JP detection → write to library).
- UI: `lib/ui/screens/import_screen.dart` — file picker for original + optional paired translation; status snackbar; routes back to library on success.

### Translation

`lib/services/translation/translate_service.dart`:
- Paragraph → sentence → hard 4500-char chunking via `splitForTranslation()`.
- Provider chain: Google Translate `gtx` first (no key, returns JSON segments), LibreTranslate mirrors as fallback (argosopentech.com, libretranslate.de).
- Per-chunk progress callback for the reader's "Translate chapter" UI; `CancelToken` aborts mid-translation.
- Smoke-tested live: short and multi-paragraph Japanese translate cleanly.

Wired into the reader's bottom-bar Translate button: opens a non-dismissable progress sheet, persists the result onto the chapter, switches the view mode to parallel.

### Sources

`lib/services/sources/`:
- `source_types.dart` — abstract `FeedSource` / `SearchSource` interfaces, `BookStub`, `ArticleStub`, `ChapterStub`, `SearchQuery`, enums.
- `session_client.dart` — cookie-aware HTTP client built on `dart:io HttpClient`. Follows redirects manually so cookies set mid-chain survive (NHK Easy's `/tix/build_authorize` flow needs this). RFC-6265-ish domain matching so a cookie on `web.nhk` reaches `news.web.nhk`.
- `nhk_auth.dart` — the one-shot NHK handshake (`/tix/build_authorize`, `profileType=abroad`, Tokyo postal defaults), memoized per `SessionClient` and shared by both NHK adapters.
- `nhk_easy.dart` — feed adapter. Hits `top-list.json` with the JWT cookie from the handshake. Parses article HTML via the `html` package, strips `<rt>/<rp>` ruby.
- `nhk_news.dart` — regular NHK News Web feed adapter. Lists via the public RSS (`www3.nhk.or.jp/rss/news/cat0.xml`); article bodies live on `news.web.nhk/newsweb/na/na-{id}` and are only fully server-rendered with the handshake cookies. The newsweb pages use hashed CSS classes, so the body extractor self-calibrates: the first `<p>` after the `<h1>` is the lead, and every body paragraph shares its exact class attribute.
- `mainichi.dart` — Mainichi Shimbun breaking-news feed (RDF RSS + `section.articledetail-body` scrape). Premium articles are detected via the `cXenseParse:mai-fee-charging` meta and imported with their free portion plus a notice.
- `rss.dart` — minimal RSS 2.0 + RDF/RSS 1.0 item parser (incl. RFC-822 dates) shared by the feed adapters.
- `syosetu.dart` — search adapter. Calls `api.syosetu.com/novelapi/api/` with `order=hyoka` etc. Scrapes the `.p-eplist__sublist` TOC and `.p-novel__text` chapter body; 600 ms throttle between chapters.
- `source_registry.dart`, `source_import.dart`, `providers/sources_provider.dart`.
- `source_import.dart`'s `SourceImporter` handles both shapes:
  - Articles → append into a rolling `feed:<sourceId>` novel; dedup by `sourceUrl`.
  - Books → new novel with all chapters; reports progress through an `ImportTask` (with cancel).

UI: `lib/ui/screens/sources_screen.dart` — single search bar, source-filter chips generated from the registry, order + completion popup, articles + books mixed in one scroll. One-tap **+** button on every result imports (instant for articles, progress sheet for books); already-imported items show a checkmark that removes them on tap (with confirm). Article tiles show an approximate JLPT difficulty badge estimated from title + summary. Tap-through on books opens a detail bottom sheet with summary, tags, and a big "Add to library" button.

### Front page (news)

`lib/ui/screens/news_screen.dart` (`/news`) renders every imported feed article as a Japanese daily rather than a feed. `lib/ui/widgets/newspaper.dart` holds the furniture, `lib/ui/widgets/front_page.dart` the layout.

- **Masthead** — `NewspaperMasthead`: romaji overline, the outlet's name in heavy kanji (`Source.nativeName`, e.g. 毎日新聞 / NHKニュース; the combined edition is 言葉新聞), an edition `SealBox` (朝刊 / 夕刊), and a Japanese dateline (`2026年8月31日（月）` · `全128件`). Day boundaries are `NewsSectionRule`s set as 【今日】/【昨日】/【8月30日】.
- **Two-column masonry** — `FrontPageBand` deals stories into the currently-shortest column using `estimateHeight`. Phones always get exactly 2 columns; wider windows get up to 5 (`FrontPageBand.columnsFor`). Bands are fixed slices of the list so the page stays inside a `ListView.builder` — building every story eagerly would tokenize every article for its difficulty badge on first paint. Column rules are painted by a `CustomPainter` behind the `Row`, because a stretched flex child can't take an unbounded height inside a `ListView`.
- **Story block** — `FrontPageStory`: a reverse-type `KickerBox` with the outlet, the time, the difficulty badge, an accent rule down the headline when unread, the cut, a justified 3-line snippet, closing hairline. Long-press removes a story.
- **Cuts** — three cases. A story whose source published an image renders it through `NewsThumb`. A story the source never offered one for gets a `NewsprintPlaceholder` two times in three (`FrontPageStory.wantsPlaceholder`, a hash of the story id): a faint field of `NewsprintPainter` column copy with the headline's first kanji set large behind it — not all of them, because a page where every story has a picture box looks like a template and one with none looks broken. A story whose image *fails to load* goes text-only: `NewsThumb.onUnavailable` fires and the block drops the picture box, rather than leaving a grey rectangle or pretending we had art. `estimateHeight` matches the same three cases so the columns stay balanced.
- **Images are captured, not hot-linked** — `NewsImageStore` (`lib/services/sources/news_image_store.dart`) downloads each lead image at import time through the adapters' `SessionClient` and stores the bytes in the `news_images` box, rewriting `Chapter.imageUrl` to `local:<key>`. NHK serves its article images from `news.web.nhk`, which answers 401 to anything without the session cookie the feed handshake negotiates — `Image.network` has no cookie jar, so every NHK picture used to render as a broken box. Capturing also makes the front page draw instantly and work offline. The box is capped at `maxImages` (oldest evicted first) and an article's image is dropped with the article.
- **Type weights** — headlines cap at `w700`. Android's `serif` family has no CJK coverage, so Japanese falls through to Noto Serif/Sans CJK, which ships Regular and Bold and *synthesises* anything heavier; at w800+ the strokes of a dense kanji smear together and the headline stops being readable.
- **Switching papers** — swipe left/right anywhere on the page (wraps around). In full mode a `PaperTab` rack is also pinned at the top with unread counts; `?paper=<id>` deep-links to one paper, and the library opens a `SourceType.feed` novel here instead of the reader.
- **Foldable days** — each day is a `DaySection` with a `NewsDayHeader`: date, story count, a fold chevron and a "+" that fetches that day. A folded day contributes its header and nothing else, which is also the cheapest way to make a long paper scroll well. `buildDayRows` (generic, in `front_page.dart`, so it's testable without a library or tokenizer behind it) does the grouping. Fold state is session-only — folding is a reading gesture, not a setting.
- **No hard refresh** — the screen holds the last rendered list (`_lastArticles`) and ignores the provider's loading state, so a sync only ever adds stories instead of flashing a spinner. Combined with `SourceImporter.importArticles` batching a whole source into one library write, a ten-article fetch redraws the page once.
- **Stable tile heights** — a story's cut (`FrontPageStory.cutFor`) is decided **synchronously**, from the item plus a process-wide set of URLs already known to have failed. Layout (`estimateHeight`) and paint both read it, and the meta row is pinned to a fixed height so a difficulty badge arriving after an async estimate can't reflow it either. This matters more than it looks: tiles are destroyed when their band scrolls out and rebuilt when it scrolls back, so a verdict living on the tile meant every pass built tall, discovered the broken image a frame later and collapsed — shifting everything below and yanking the scroll position toward the bottom, repeatedly. `test/front_page_test.dart` pins the invariant, including that a known-broken image lays out no box at all on the first frame.
- **Scroll cost** — the expensive thing on this screen was the difficulty badge: deriving one meant tokenizing the article as it scrolled into view. `Chapter.jlptStats` is now computed once at import (`SourceImporter._scoreDifficulty`) and handed to `DifficultyBadge` as `stats`, which then does no work at all. Articles imported before that fall back to estimating on demand, from the same `JlptEstimator.sample` window so old and new articles score alike. The list also turns off automatic keep-alives, and snippets are cut from the first 240 characters rather than running a whitespace regex over whole article bodies.
- The old linear layouts are still reachable through the view-mode button (`list` / `card`); `grid` means the front page here.

### Reading mode

`ReaderPrefs.simpleMode` (**on by default**) strips the app back to the three things it does: shelves, the front page, the reader.

- Library: no filter bar, no sort, no view-mode switch, no import FAB; shelves are forced. App bar is News + Settings.
- Front page: no rack (a `_PaperDots` tick strip instead), no view-mode or unread filter, one fetch button (今日の新聞). Papers change by swiping.
- Settings: the hub hides "Saved vocabulary" and "Browse sources"; the Japanese screen hides the JLPT matrix.
- `SourceManagerScreen` (`/sources/manage`) is the only source configuration surface — one switch per outlet, carried papers listed above the rest. Stories from a paper that's been switched off leave the front page but are not deleted.

### Library shelves

`LibraryViewMode.grid` renders as shelves (`lib/ui/widgets/shelf.dart`). `BookShelf` takes a column count and hands each slot its width, so covers, mastheads and captions all scale off one number; `ShelfBoard` draws the contact shadow, board face and front edge under each row. Covers are smaller than the old grid (~124 px target) so a shelf holds more. Part-full shelves keep their empty slots so covers stay on a common grid.

Covers lean back a few degrees about their bottom edge (`_CoverWithShadow.leaning`, a perspective `Matrix4` — the `setEntry(3, 2, …)` term is what makes it depth rather than an orthographic squash), so they read as standing on the shelf against the wall behind. Content-type and language badges sit along the *bottom* edge: a cover's title is at the top, and on a newspaper front the masthead is the whole tile.

Feed novels aren't books: with no cover URL, `BookCover` renders a `NewspaperFront` — the outlet's name set as a masthead over `NewsprintPainter` column copy, with a story-count kicker — and no caption underneath, since the masthead already names it. The "Continue reading" row is gone; `lastReadAt` is still tracked and still drives the `recent` sort.

`newsArticlesProvider` (in `lib/providers/news_provider.dart`) flattens the rolling feed novels and recomputes whenever the library changes. Read state lives in `news_read_ids` in the prefs box via `newsReadProvider`. Tapping a story marks it read and deep-links into the reader (`/reader/:id?ch=N`); a "Next story" card at the end of each article hands off to the next one so reading a feed is a continuous scroll.

Getting *out* of the reader takes both the back arrow and a `PopScope`: the reader is entered with `go`, which replaces the stack, so the system back gesture would otherwise land on the library rather than the paper the story came from. Both call `_backRoute`. Article headlines render through `JapaneseText`, so they're colour-coded and tappable like the body — for a news story that's where the hardest vocabulary is.

### The newsstand

`SourceRegistry` carries ten feed sources. Three ship on — NHK News Web Easy, NHK's top-stories wire, and the Mainichi's breaking desk — and the other seven (NHK 社会 / 政治 / 経済 / 国際 / 科学・医療 / 文化・エンタメ / スポーツ) are off until switched on in the source manager, so a fresh install starts readable rather than exhaustive.

The desks are the same two adapters parameterised: `NhkDesk` picks the RSS category and `MainichiDesk` the feed, so every desk reuses body extraction that's already proven. `Source.enabledByDefault` marks the flagships; `ReaderPrefsNotifier.carriedSources` resolves `ReaderPrefs.enabledSourceIds`, where the empty list means "whatever the app ships on by default" so a source added later appears without the user opting in. The three flagship ids (`nhk-easy`, `nhk-news`, `mainichi`) are load-bearing — feed novels are keyed `feed:<sourceId>` — and a test pins them.

Which feeds made the cut was decided by `dart run tool/smoke_desks.dart`, which lists and fetches from every registered source. NHK 暮らし links to lifestyle landing pages that don't survive the article-id filter; the Mainichi's section feeds are stale placeholders, `mainichi.rss` mixes landing pages into the stories, and `opinion.rss` serves the flash feed verbatim. None of them are registered. NHK expires individual articles off newsweb, so a 404 partway down a feed is normal and the batch importer skips it.

### Bulk fetching

`lib/services/sources/feed_sync.dart` — `FeedSync.run({sources, mode})` is the one path for pulling articles in bulk, exposed as `feedSyncProvider`.

`FeedFetchMode`:
- `today` — everything published today; if today's edition isn't out yet, the whole of the newest day the feed carries (NHK Easy publishes on a lag, so a literal "today" filter often returned an empty paper).
- `latest10` / `latest30` — the N newest unimported stories.
- `day` — everything filed on one calendar day, paired with the `day` argument.

`FeedSync.survey` lists every carried source once and buckets what *isn't* already imported by publication day, so the fetch sheet can offer back issues by date with counts ("8月30日 · 14 new") instead of an undifferentiated "latest N". That's the orderly path; the latest-N modes remain as shortcuts. Day headers on the page carry the same action for their own date.

Every mode skips already-imported `sourceUrl`s, sorts newest-first, and is capped at `FeedSync.maxPerSource` (40) per pass. Surfaced as buttons under the masthead, the fetch sheet in the app bar, pull-to-refresh, per-day "+" on the day headers, and a per-source bulk menu in the browse screen.

### Difficulty estimation

`lib/services/dictionary/jlpt_estimator.dart` — tokenizes a text (first 4k chars) and buckets content words (noun/verb/adjective/adverb) against the JLPT table into `JlptStats` (via `estimate`, so unlisted compounds score rather than collapsing into "unknown"); `difficultyBucket` gives the closest level. Memoized per text. `DifficultyBadge` (`lib/ui/widgets/difficulty_badge.dart`) renders the estimate ("~N3" when approximate) and optionally a stacked N5…N1 share bar; renders nothing when the tokenizer is unavailable (web stub).

Smoke tests under `tool/` for offline verification:
- `dart run tool/smoke_desks.dart` — lists and fetches from every registered feed source; the gate for adding a desk.
- `dart run tool/smoke_sources.dart` — hits Syosetu search + chapter, NHK Easy list + article.
- `dart run tool/smoke_news_sources.dart` — lists + fetches the first article from all three news feeds (NHK Easy, NHK News, Mainichi).
- `dart run tool/smoke_translate.dart` — checks ja → en against gtx + the chunk splitter.

### Vocab export (AnkiDroid)

`lib/services/export/vocab_export.dart`:
- `toTsv(entries, opts)` — pure function. UTF‑8 TSV, columns: Front (kanji surface), Reading (kana), Back (semicolon-joined glosses), PartsOfSpeech, Example, Source (novel title + URL), Tags (space-separated, AnkiDroid convention). Tabs/newlines inside fields collapsed to spaces so every entry is exactly one row.
- `VocabExporter.exportAll(opts)` — writes a BOM-prefixed TSV to a temp file and hands it to `Share.shareXFiles`. AnkiDroid (and any other text-handling app) appears in the share sheet. After a successful share, every exported entry's `exportedAt` is bumped so subsequent "Export new since last" works.
- `ExportOptions { since, header }` — `since` filters to entries added after a timestamp; `header` prepends the column-name row.

UI: `lib/ui/screens/vocab_screen.dart` — sort menu (recent / alpha / JLPT level), text filter, swipe-to-delete with confirm, JLPT badge + cloud icon for previously-exported entries, share button in the AppBar that opens an export sheet with three options ("Everything", "New since last export", "Everything, with header row").

## Android build notes

The Android build needs a few compat shims (see `android/build.gradle.kts` and
`android/gradle.properties`):
- AGP 8 requires every Android library to declare a `namespace`; older plugins
  used the legacy `<manifest package="…">` attribute. We backfill it.
- Plugins may compile their Java side at a different JVM target than the
  Kotlin side; we align Kotlin to whatever the plugin's Java is set to.
- `minSdk = 21` (raised from Flutter's default 16) for native plugins that
  bundle NDK platform-21 code.
- The NDK is **pinned** (`ndkVersion = "28.2.13676358"`) rather than tracking
  `flutter.ndkVersion`, because the F-Droid recipe has to name an NDK its
  buildserver provides and it must match what the vendored MeCab is compiled
  against here.

### Release packaging

One APK per ABI. Version codes are `buildNumber * 10 + abi` (armeabi-v7a=1,
arm64-v8a=2, x86_64=3), applied by a `versionCodeOverride` block in
`android/app/build.gradle.kts`. That's the scheme F-Droid's submission guide
asks for; Flutter's own `--split-per-abi` scheme puts the ABI in the *high*
digits (1000/2000/4000 + code), which leaves no room to grow and sorts x86_64
above a later arm64 release. The build number jumped to 210 when the scheme
changed — the last release under the old one shipped arm64 as 2012, and Android
refuses an update whose versionCode went backwards.

Release builds sign with a real keystore when `android/key.properties` exists,
and fall back to the debug key when it doesn't, so a fresh clone still produces
installable release APKs. F-Droid signs with its own key, so its recipe deletes
the line marked `FDROID-STRIP` during prebuild — **exactly one line in that file
may carry the marker**, which a test enforces. Keying the strip off a marker
rather than the shape of the code is deliberate: the code changed once and broke
the old `sed` silently.

`test/fdroid_metadata_test.dart` checks the recipe in `fdroid/` against the app:
versionCodes against `pubspec.yaml` and gradle's ABI map, `VercodeOperation`
against the declared codes and their required ordering, that no code regresses
below the old scheme, that `commit` is a full hash pointing at the release tag,
the pinned NDK, and the marker's uniqueness. Run it before touching either file
— an F-Droid build cycle takes the better part of an hour to tell you the same
thing.

## Migration status

| Subsystem                          | Status     |
|------------------------------------|------------|
| Data models                        | ✅ done    |
| Hive storage                       | ✅ done    |
| 11 builtin themes + theme picker   | ✅ done    |
| Riverpod providers                 | ✅ done    |
| Navigation (go_router)             | ✅ done    |
| Library screen                     | ✅ done    |
| Reader screen (skeleton)           | ✅ done    |
| Reader settings panel              | ✅ done    |
| Japanese tokenizer (MeCab)         | ✅ done    |
| JLPT vocab bundling + lookup       | ✅ done    |
| JapaneseText w/ JLPT colors        | ✅ done    |
| Jisho dictionary popover           | ✅ done    |
| Translation service                | ✅ done    |
| TTS                                | ⊘ skipped (per request)  |
| EPUB / TXT importers               | ✅ done    |
| Sources adapters (NHK, Syosetu)    | ✅ done    |
| Vocab Anki export                  | ✅ done    |

## Working with legacy_ts/

When porting a behavior, the legacy file is usually the canonical spec. Common lookups:

- Reader prefs defaults / theme list: `legacy_ts/packages/core/src/context/ReaderPrefsContext.tsx`, `legacy_ts/packages/core/src/data/readerThemes.ts`
- Data types: `legacy_ts/packages/core/src/data/types.ts`
- JLPT vocab table (~8k entries): `legacy_ts/packages/core/src/data/jlptVocab.full.ts`
- JP tokenizer: `legacy_ts/packages/core/src/utils/jpTokenizer.ts`
- Dictionary lookup: `legacy_ts/packages/core/src/utils/jpDictLookup.ts`
- JLPT stats: `legacy_ts/packages/core/src/utils/jlptStats.ts`
- Translation: search `legacy_ts/packages/core/src/utils/` for `translate`
- EPUB / TXT / cleaner: `legacy_ts/packages/core/src/sources/`
- Reader / Library / Settings React UI: `legacy_ts/packages/ui/src/`

`legacy_ts/` is gitignored at the `node_modules/` level — the source files are version controlled, the build artifacts are not.

## Conventions

- Use `flutter_riverpod` providers; do not call `Hive.box(...)` directly from widgets — go through providers.
- Models stay JSON-serializable via `toJson` / `fromJson` (no `hive_generator`). This makes export/import and migration trivial.
- New screens go in `lib/ui/screens/`; new shared widgets in `lib/ui/widgets/`.
- Strings are UI-only and inlined; we'll add i18n later if needed.
- Stick to Material 3 with the active theme's `ColorScheme`; avoid inline colors except where the design calls for the theme's literal bg/fg/accent.
