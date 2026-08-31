import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'screens/book_detail_screen.dart';
import 'screens/import_screen.dart';
import 'screens/library_screen.dart';
import 'screens/news_screen.dart';
import 'screens/reader_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/source_manager_screen.dart';
import 'screens/sources_screen.dart';
import 'screens/vocab_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      name: 'library',
      builder: (ctx, st) => const LibraryScreen(),
      routes: [
        GoRoute(
          path: 'reader/:novelId',
          name: 'reader',
          builder: (ctx, st) => ReaderScreen(
            novelId: st.pathParameters['novelId']!,
            initialChapter:
                int.tryParse(st.uri.queryParameters['ch'] ?? ''),
          ),
          routes: [
            GoRoute(
              path: 'settings',
              name: 'reader-settings',
              builder: (ctx, st) => const ReaderSettingsScreen(),
            ),
          ],
        ),
        GoRoute(
          path: 'book/:novelId',
          name: 'book',
          builder: (ctx, st) =>
              BookDetailScreen(novelId: st.pathParameters['novelId']!),
        ),
        GoRoute(
          path: 'import',
          name: 'import',
          builder: (ctx, st) => const ImportScreen(),
        ),
        GoRoute(
          path: 'vocab',
          name: 'vocab',
          builder: (ctx, st) => const VocabScreen(),
        ),
        GoRoute(
          path: 'sources',
          name: 'sources',
          builder: (ctx, st) => const SourcesScreen(),
          routes: [
            GoRoute(
              path: 'manage',
              name: 'source-manager',
              builder: (ctx, st) => const SourceManagerScreen(),
            ),
          ],
        ),
        GoRoute(
          path: 'news',
          name: 'news',
          builder: (ctx, st) =>
              NewsScreen(initialPaper: st.uri.queryParameters['paper']),
        ),
        GoRoute(
          path: 'settings',
          name: 'settings',
          builder: (ctx, st) => const ReaderSettingsScreen(),
        ),
      ],
    ),
  ],
  errorBuilder: (ctx, state) => Scaffold(
    appBar: AppBar(title: const Text('Not found')),
    body: Center(child: Text('No route: ${state.uri}')),
  ),
);
