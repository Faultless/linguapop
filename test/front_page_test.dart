import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linguapop/ui/widgets/front_page.dart';
import 'package:linguapop/ui/widgets/newspaper.dart';

FrontPageItem item(String id, {String? title, String? image, bool read = false}) =>
    FrontPageItem(
      id: id,
      title: title ?? '記事の見出し $id',
      snippet: '本文の書き出しがここに入ります。' * 3,
      sourceName: 'NHK NEWS WEB',
      imageUrl: image,
      publishedAt: DateTime(2026, 8, 31, 9, 5).millisecondsSinceEpoch,
      read: read,
    );

/// Pumps a band the way the front page does: inside a vertically-unbounded
/// `ListView`, which is exactly the constraint that a stretched flex child
/// would blow up on.
Future<void> pumpBand(
  WidgetTester tester,
  List<FrontPageItem> items, {
  int columns = 2,
  double width = 400,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          height: 800,
          child: ListView(
            children: [
              FrontPageBand(
                items: items,
                columns: columns,
                showDifficulty: false,
                onOpen: (_) {},
              ),
            ],
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  group('column count', () {
    test('phones always get exactly two columns', () {
      expect(FrontPageBand.columnsFor(360), 2);
      expect(FrontPageBand.columnsFor(412), 2);
      expect(FrontPageBand.columnsFor(639), 2);
    });

    test('wider windows get more columns, capped at five', () {
      expect(FrontPageBand.columnsFor(900), 3);
      expect(FrontPageBand.columnsFor(1280), 4);
      expect(FrontPageBand.columnsFor(4000), 5);
    });
  });

  group('dealing stories into columns', () {
    test('every story lands in exactly one column', () {
      final items = [for (var i = 0; i < 9; i++) item('$i')];
      final buckets = FrontPageBand.deal(items, 2, 180);
      final flat = buckets.expand((b) => b).map((i) => i.id).toList();
      expect(flat.length, items.length);
      expect(flat.toSet(), items.map((i) => i.id).toSet());
    });

    test('columns stay balanced when heights differ wildly', () {
      final items = [
        item('tall', title: '見出し' * 30, image: 'https://example.com/a.jpg'),
        for (var i = 0; i < 5; i++) item('short$i', title: '短い'),
      ];
      final buckets = FrontPageBand.deal(items, 2, 180);
      final heights = [
        for (final b in buckets)
          b.fold<double>(
              0, (sum, i) => sum + FrontPageBand.estimateHeight(i, 180)),
      ];
      // The tall story shouldn't drag one column to twice the other.
      final ratio = heights.reduce((a, b) => a > b ? a : b) /
          heights.reduce((a, b) => a < b ? a : b);
      expect(ratio, lessThan(2.0));
    });

    test('a story with a cut is estimated taller than a bare one', () {
      // Same title everywhere so only the picture box moves the number.
      const title = '同じ長さの見出し';
      final ids = List.generate(60, (i) => 'story-$i');
      final bare =
          ids.firstWhere((id) => !FrontPageStory.wantsPlaceholder(id));
      final drawn = ids.firstWhere(FrontPageStory.wantsPlaceholder);

      double h(String id, {String? image}) => FrontPageBand.estimateHeight(
          item(id, title: title, image: image), 180);

      expect(h(drawn), greaterThan(h(bare)),
          reason: 'a drawn placeholder takes the same room as a photo');
      expect(h(bare, image: 'https://example.com/a.jpg'), greaterThan(h(bare)));
    });
  });

  group('image placeholders', () {
    test('the same story always gets the same answer', () {
      for (final id in ['a', 'story-7', '毎日/12345']) {
        expect(FrontPageStory.wantsPlaceholder(id),
            FrontPageStory.wantsPlaceholder(id));
      }
    });

    test('a page of picture-less stories gets a mix, not all or nothing', () {
      final ids = List.generate(60, (i) => 'story-$i');
      final drawn = ids.where(FrontPageStory.wantsPlaceholder).length;
      expect(drawn, greaterThan(10));
      expect(drawn, lessThan(ids.length));
    });

    test('the placeholder glyph is the headline\'s first kanji', () {
      expect(NewsprintPlaceholder.glyphFor('政府が発表'), '政');
      expect(NewsprintPlaceholder.glyphFor('あすの てんき'), '新');
      expect(NewsprintPlaceholder.glyphFor(''), '新');
    });
  });

  group('rendering', () {
    testWidgets('lays out inside an unbounded ListView without overflowing',
        (tester) async {
      await pumpBand(tester, [for (var i = 0; i < 8; i++) item('$i')]);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('記事の見出し'), findsNWidgets(8));
    });

    testWidgets('renders two side-by-side columns on a phone width',
        (tester) async {
      final items = [for (var i = 0; i < 6; i++) item('$i')];
      await pumpBand(tester, items, width: 400);
      // Stories are dealt alternately at equal heights, so ids 0 and 1 land in
      // different columns and must not share an x position.
      final first = tester.getTopLeft(find.text('記事の見出し 0'));
      final second = tester.getTopLeft(find.text('記事の見出し 1'));
      expect(first.dx, isNot(second.dx));
      expect((first.dx - second.dx).abs(), greaterThan(100));
    });

    testWidgets('stories with images still lay out', (tester) async {
      await pumpBand(tester, [
        for (var i = 0; i < 4; i++)
          item('$i', image: 'https://example.com/$i.jpg'),
      ]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('masthead and paper rack fit a narrow phone', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: ListView(children: [
              const NewspaperMasthead(
                title: 'NHK NEWS WEB EASY',
                overline: 'LinguaPop',
                leftMeta: 'August 31, 2026',
                rightMeta: '128 stories',
              ),
              const NewsSectionRule(label: 'Today'),
              Row(children: [
                PaperTab(
                    name: 'All papers',
                    unread: 12,
                    selected: true,
                    onTap: () {}),
                const SizedBox(width: 8),
                PaperTab(
                    name: 'Mainichi', unread: 0, selected: false, onTap: () {}),
              ]),
            ]),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping a headline reports the story', (tester) async {
      FrontPageItem? tapped;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(children: [
            FrontPageBand(
              items: [item('a'), item('b')],
              columns: 2,
              showDifficulty: false,
              onOpen: (i) => tapped = i,
            ),
          ]),
        ),
      ));
      await tester.tap(find.text('記事の見出し b'));
      expect(tapped?.id, 'b');
    });
  });
}
