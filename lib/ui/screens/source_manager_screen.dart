import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/prefs_provider.dart';
import '../../providers/sources_provider.dart';
import '../../services/sources/source_types.dart';
import '../widgets/newspaper.dart';

/// Which papers the newsstand carries.
///
/// Deliberately the only source-configuration surface in reading mode: a list
/// of outlets with a switch each. Everything is on by default, so a fresh
/// install has a full newsstand without a setup step.
class SourceManagerScreen extends ConsumerWidget {
  const SourceManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final registry = ref.watch(sourceRegistryProvider);
    final prefs = ref.watch(readerPrefsProvider);
    final notifier = ref.read(readerPrefsProvider.notifier);

    final feeds = registry.feedSources.toList();
    final allIds = [for (final s in feeds) s.id];
    final enabled = prefs.enabledSourceIds.isEmpty
        ? allIds.toSet()
        : prefs.enabledSourceIds.toSet();

    return Scaffold(
      appBar: AppBar(title: const Text('Papers')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Papers on the stand. Switching one off hides its stories from '
              'the front page and skips it when fetching — nothing already '
              'downloaded is deleted.',
              style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: cs.onSurface.withValues(alpha: 0.65)),
            ),
          ),
          const SizedBox(height: 6),
          for (final s in feeds)
            _SourceTile(
              source: s,
              enabled: enabled.contains(s.id),
              onChanged: (v) => notifier.setSourceEnabled(s.id, v, allIds),
            ),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('LIBRARIES',
                style: NewsprintStyle.meta(cs, size: 10)
                    .copyWith(letterSpacing: 1.6)),
          ),
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
      title: Text(
        source.nativeName ?? source.name,
        style: const TextStyle(
            fontFamily: NewsprintStyle.serif,
            fontSize: 16,
            fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        source.nativeName == null
            ? (source.description ?? source.name)
            : '${source.name} · ${source.description ?? ""}'.trim(),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style:
            TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6)),
      ),
    );
  }
}
