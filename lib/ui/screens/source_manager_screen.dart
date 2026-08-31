import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/prefs_provider.dart';
import '../../providers/sources_provider.dart';
import '../../services/sources/source_types.dart';
import '../widgets/newspaper.dart';

/// Which papers the newsstand carries.
///
/// Deliberately the only source-configuration surface in reading mode: a list
/// of outlets with a switch each. A handful are on out of the box — NHK's easy
/// edition, NHK's main wire, and the Mainichi's breaking desk — and the rest
/// are here to be switched on, so the stand starts readable instead of
/// exhaustive.
class SourceManagerScreen extends ConsumerWidget {
  const SourceManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final registry = ref.watch(sourceRegistryProvider);
    final prefs = ref.watch(readerPrefsProvider);
    final notifier = ref.read(readerPrefsProvider.notifier);

    final feeds = registry.feedSources.toList();
    final defaultIds = registry.defaultFeedIds.toList();
    final carried =
        ReaderPrefsNotifier.carriedSources(prefs, registry.defaultFeedIds);

    // Carried papers first so the stand you actually have is at the top,
    // then the rest in registry order (flagships before desk feeds).
    final on = feeds.where((s) => carried.contains(s.id)).toList();
    final off = feeds.where((s) => !carried.contains(s.id)).toList();

    Widget tile(FeedSource s) => _SourceTile(
          source: s,
          enabled: carried.contains(s.id),
          onChanged: (v) => notifier.setSourceEnabled(s.id, v, defaultIds),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Papers')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Switching a paper off hides its stories from the front page and '
              'skips it when fetching. Nothing already downloaded is deleted.',
              style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: cs.onSurface.withValues(alpha: 0.65)),
            ),
          ),
          _Heading(label: 'ON THE STAND · ${on.length}'),
          for (final s in on) tile(s),
          if (off.isNotEmpty) ...[
            _Heading(label: 'ALSO AVAILABLE · ${off.length}'),
            for (final s in off) tile(s),
          ],
          const Divider(height: 32),
          _Heading(label: 'LIBRARIES'),
          for (final s in registry.searchSources)
            ListTile(
              title: Text(s.nativeName ?? s.name),
              subtitle: Text(s.description ?? s.name),
              trailing: const Icon(Icons.search, size: 18),
            ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  final String label;
  const _Heading({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(label,
          style:
              NewsprintStyle.meta(cs, size: 10).copyWith(letterSpacing: 1.6)),
    );
  }
}

class _SourceTile extends StatelessWidget {
  final FeedSource source;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  const _SourceTile({
    required this.source,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SwitchListTile(
      value: enabled,
      onChanged: onChanged,
      dense: true,
      title: Text(
        source.nativeName ?? source.name,
        style: const TextStyle(
            fontFamily: NewsprintStyle.serif,
            fontSize: 15.5,
            fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        source.description ?? source.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            fontSize: 11.5, color: cs.onSurface.withValues(alpha: 0.6)),
      ),
    );
  }
}
