import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/dict_entry.dart';
import '../../data/models/jp_token.dart';
import '../../data/models/vocab_entry.dart';
import '../../data/themes/builtin_themes.dart';
import '../../providers/dict_provider.dart';
import '../../providers/jlpt_provider.dart';
import '../../providers/vocab_provider.dart';
import 'jlpt_badge.dart';

const _uuid = Uuid();

/// Bottom-sheet popover that fetches and displays a Jisho dictionary entry
/// for a tapped token, with a "Save to vocab" action.
Future<void> showWordPopover(
  BuildContext context, {
  required JpToken token,
  String? exampleSentence,
  String? sourceNovelId,
  String? sourceNovelTitle,
  String? sourceChapterId,
  int? sourceChapterIndex,
}) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      return _WordPopover(
        token: token,
        exampleSentence: exampleSentence,
        sourceNovelId: sourceNovelId,
        sourceNovelTitle: sourceNovelTitle,
        sourceChapterId: sourceChapterId,
        sourceChapterIndex: sourceChapterIndex,
      );
    },
  );
}

class _WordPopover extends ConsumerStatefulWidget {
  final JpToken token;
  final String? exampleSentence;
  final String? sourceNovelId;
  final String? sourceNovelTitle;
  final String? sourceChapterId;
  final int? sourceChapterIndex;

  const _WordPopover({
    required this.token,
    this.exampleSentence,
    this.sourceNovelId,
    this.sourceNovelTitle,
    this.sourceChapterId,
    this.sourceChapterIndex,
  });

  @override
  ConsumerState<_WordPopover> createState() => _WordPopoverState();
}

class _WordPopoverState extends ConsumerState<_WordPopover> {
  late Future<DictResult> _future;

  @override
  void initState() {
    super.initState();
    final service = ref.read(jishoServiceProvider);
    _future = service.lookupWord(
      widget.token.base,
      fallback: widget.token.surface != widget.token.base
          ? widget.token.surface
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      builder: (ctx, ctrl) {
        return ListView(
          controller: ctrl,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            _Header(token: widget.token),
            const SizedBox(height: 16),
            FutureBuilder<DictResult>(
              future: _future,
              builder: (ctx, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snap.hasError) {
                  return _ErrorBlock(message: snap.error.toString());
                }
                final result = snap.data!;
                if (result.entries.isEmpty) {
                  return const _ErrorBlock(
                      message:
                          'No dictionary entry found for this word.');
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final e in result.entries) ...[
                      _EntryBlock(entry: e),
                      const SizedBox(height: 12),
                    ],
                    const SizedBox(height: 4),
                    FilledButton.tonalIcon(
                      onPressed: () => _saveToVocab(result),
                      icon: const Icon(Icons.bookmark_add_outlined),
                      label: const Text('Save to vocab'),
                    ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveToVocab(DictResult result) async {
    final tk = widget.token;
    final best = result.entries.isEmpty ? null : result.entries.first;
    final entry = VocabEntry(
      id: _uuid.v4(),
      base: tk.base,
      surface: tk.surface,
      reading: tk.reading ?? (best?.readings.isNotEmpty == true ? best!.readings.first : null),
      jlptLevel: best?.jlptLevel,
      partsOfSpeech: best == null || best.senses.isEmpty
          ? null
          : best.senses.first.partsOfSpeech,
      glosses: best == null
          ? const []
          : best.senses
              .expand((s) => s.definitions)
              .take(6)
              .toList(),
      exampleSentence: widget.exampleSentence,
      sourceNovelId: widget.sourceNovelId,
      sourceNovelTitle: widget.sourceNovelTitle,
      sourceChapterId: widget.sourceChapterId,
      sourceChapterIndex: widget.sourceChapterIndex,
      addedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await ref.read(vocabProvider.notifier).upsert(entry);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved "${tk.surface}" to vocab.')),
    );
  }
}

class _Header extends ConsumerWidget {
  final JpToken token;
  const _Header({required this.token});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final hit = ref.watch(jlptLookupProvider).estimate(
          base: token.base,
          surface: token.surface,
          reading: token.reading,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(token.surface,
                  style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      height: 1.1)),
            ),
            if (hit != null)
              JlptBadge(
                  level: hit.level, size: 12, approximate: hit.approximate),
          ],
        ),
        if (token.reading != null && token.reading != token.surface)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              token.reading!,
              style: TextStyle(
                  fontSize: 16,
                  color: cs.onSurface.withValues(alpha: 0.7)),
            ),
          ),
        if (token.base != token.surface)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'base form: ${token.base}',
              style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.55)),
            ),
          ),
        if (token.conjugation != null)
          _ConjugationBlock(info: token.conjugation!),
      ],
    );
  }
}

/// Explains the conjugation of a merged verb/adjective phrase: form labels as
/// chips, plus the morpheme-by-morpheme breakdown.
class _ConjugationBlock extends StatelessWidget {
  final ConjugationInfo info;
  const _ConjugationBlock({required this.info});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (info.forms.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final f in info.forms)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      f,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
                    ),
                  ),
              ],
            ),
          if (info.parts.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text.rich(
                TextSpan(
                  children: [
                    for (var i = 0; i < info.parts.length; i++) ...[
                      if (i > 0)
                        TextSpan(
                          text: ' + ',
                          style: TextStyle(
                              color: cs.onSurface.withValues(alpha: 0.4)),
                        ),
                      TextSpan(
                        text: info.parts[i].surface,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (info.parts[i].role.isNotEmpty &&
                          info.parts[i].role != 'stem')
                        TextSpan(
                          text: ' (${info.parts[i].role})',
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurface.withValues(alpha: 0.55),
                          ),
                        )
                      else if (info.parts[i].role == 'stem' &&
                          info.parts[i].base != info.parts[i].surface)
                        TextSpan(
                          text: ' (${info.parts[i].base})',
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurface.withValues(alpha: 0.55),
                          ),
                        ),
                    ],
                  ],
                ),
                style: const TextStyle(fontSize: 13, height: 1.5),
              ),
            ),
        ],
      ),
    );
  }
}

class _EntryBlock extends StatelessWidget {
  final DictEntry entry;
  const _EntryBlock({required this.entry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                          text: entry.word,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w600)),
                      if (entry.readings.isNotEmpty)
                        TextSpan(
                          text: '  ${entry.readings.join(", ")}',
                          style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurface.withValues(alpha: 0.7)),
                        ),
                    ],
                  ),
                ),
              ),
              if (entry.jlptLevel != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: JlptBadge(level: entry.jlptLevel!),
                ),
              if (entry.isCommon)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: kJlptColors[5]!.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      'common',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: kJlptColors[5]),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < entry.senses.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 18,
                    child: Text('${i + 1}.',
                        style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurface.withValues(alpha: 0.5))),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (entry.senses[i].partsOfSpeech.isNotEmpty)
                          Text(
                            entry.senses[i].partsOfSpeech.join(' · '),
                            style: TextStyle(
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                              color: cs.primary,
                            ),
                          ),
                        Text(
                          entry.senses[i].definitions.join('; '),
                          style: const TextStyle(fontSize: 14, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  final String message;
  const _ErrorBlock({required this.message});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(message, style: const TextStyle(fontSize: 14)),
    );
  }
}
