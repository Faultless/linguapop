import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linguapop/ui/widgets/newspaper.dart';
import 'package:linguapop/ui/widgets/shelf.dart';

Future<void> pumpShelf(
  WidgetTester tester, {
  required int columns,
  required int count,
  double width = 400,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: width,
        child: ListView(
          children: [
            BookShelf(
              columns: columns,
              count: count,
              itemBuilder: (ctx, i, w) => ColoredBox(
                color: Colors.blue,
                child: Center(child: Text('item$i')),
              ),
            ),
          ],
        ),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  group('BookShelf', () {
    testWidgets('lays a part-full shelf out on the same grid as a full one',
        (tester) async {
      await pumpShelf(tester, columns: 4, count: 2);
      expect(tester.takeException(), isNull);
      final first = tester.getTopLeft(find.text('item0'));
      final second = tester.getTopLeft(find.text('item1'));
      expect(second.dx, greaterThan(first.dx));
      expect(second.dy, first.dy);
      // The two empty slots still exist, so nothing re-centres.
      expect(find.text('item2'), findsNothing);
    });

    testWidgets('slot width divides the shelf evenly', (tester) async {
      const width = 400.0;
      const columns = 4;
      const spacing = 12.0;
      await pumpShelf(tester, columns: columns, count: columns, width: width);
      final slot = tester.getSize(
          find.ancestor(of: find.text('item0'), matching: find.byType(SizedBox)).first);
      const expected = (width - spacing * (columns - 1)) / columns;
      expect(slot.width, closeTo(expected, 0.01));
    });

    testWidgets('renders a board under the covers', (tester) async {
      await pumpShelf(tester, columns: 3, count: 3);
      expect(find.byType(ShelfBoard), findsOneWidget);
      final board = tester.getTopLeft(find.byType(ShelfBoard));
      final item = tester.getBottomLeft(find.text('item0'));
      expect(board.dy, greaterThanOrEqualTo(item.dy - 40));
    });

    testWidgets('a zero-width shelf degrades instead of throwing',
        (tester) async {
      await pumpShelf(tester, columns: 3, count: 3, width: 0);
      expect(tester.takeException(), isNull);
    });
  });

  group('NewspaperFront', () {
    testWidgets('sets the outlet name as its masthead', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 110,
              height: 165,
              child: NewspaperFront(outlet: '毎日新聞', kicker: '24件'),
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('毎日新聞'), findsOneWidget);
      expect(find.text('24件'), findsOneWidget);
    });

    testWidgets('survives a thumbnail-sized box', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 46,
              height: 69,
              child: NewspaperFront(outlet: 'NHKニュース'),
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('stableSeed', () {
    test('is deterministic and spreads across buckets', () {
      expect(stableSeed('abc'), stableSeed('abc'));
      expect(stableSeed('abc'), isNot(stableSeed('abd')));
      final buckets = <int>{};
      for (var i = 0; i < 40; i++) {
        buckets.add(stableSeed('story-$i') % 3);
      }
      expect(buckets, {0, 1, 2});
    });
  });
}
