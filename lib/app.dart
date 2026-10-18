import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/jlpt_provider.dart';
import 'providers/news_refresh_provider.dart';
import 'providers/prefs_provider.dart';
import 'providers/tokenizer_provider.dart';
import 'ui/router.dart';

class LinguapopApp extends ConsumerStatefulWidget {
  const LinguapopApp({super.key});

  @override
  ConsumerState<LinguapopApp> createState() => _LinguapopAppState();
}

class _LinguapopAppState extends ConsumerState<LinguapopApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Fire-and-forget warm-ups: the first IPADIC copy to disk is ~51 MB and
    // takes a few seconds, so kick it off before the user opens a chapter.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(tokenizerStatusProvider.future);
      ref.read(jlptLoadedProvider.future);
      // A next-day visit should open on today's paper, not yesterday's.
      ref.read(newsRefreshProvider.notifier).refreshCarried();
    });
    // Android keeps the process alive for days, so resume counts as a visit.
    _lifecycle = AppLifecycleListener(
        onResume: () =>
            ref.read(newsRefreshProvider.notifier).refreshCarried());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(activeThemeProvider);
    return MaterialApp.router(
      title: 'LinguaPop',
      debugShowCheckedModeBanner: false,
      theme: theme.toThemeData(),
      routerConfig: appRouter,
    );
  }
}
