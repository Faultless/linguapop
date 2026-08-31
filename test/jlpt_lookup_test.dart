import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:linguapop/services/dictionary/jlpt_lookup.dart';

/// Exercises the lookup against the *real* bundled assets, read straight off
/// disk — the bundled data is what determines coverage, so a synthetic
/// fixture would prove nothing about it.
JlptLookup buildLookup() {
  final lookup = JlptLookup();
  lookup.ingestVocab(
      jsonDecode(File('assets/jlpt/vocab.json').readAsStringSync()) as List);
  lookup.ingestStarter(
      jsonDecode(File('assets/jlpt/starter.json').readAsStringSync()) as List);
  return lookup;
}

void main() {
  late JlptLookup jlpt;
  setUpAll(() => jlpt = buildLookup());

  group('exact lookups', () {
    test('listed words keep their level and are not marked approximate', () {
      for (final w in ['学校', '食べる', '新しい', '会社']) {
        final hit = jlpt.lookup(base: w);
        expect(hit, isNotNull, reason: '$w should be listed');
        expect(hit!.approximate, isFalse);
        expect(hit.level, inInclusiveRange(1, 5));
      }
    });

    test('reading matches when the surface is written in kana', () {
      expect(jlpt.lookup(base: 'がっこう'), isNotNull);
    });
  });

  group('de-inflection fallbacks', () {
    test('五段 potential reduces to the dictionary form', () {
      // 読める is not a JLPT entry; 読む is.
      final hit = jlpt.lookup(base: '読める');
      expect(hit, isNotNull);
      expect(hit!.level, jlpt.lookup(base: '読む')!.level);
    });

    test('一段 passive reduces to the dictionary form', () {
      expect(jlpt.lookup(base: '見られる'), isNotNull);
    });

    test('suru-verb base reduces to its noun', () {
      // The conjugation merger emits 勉強する as one token's base form.
      final hit = jlpt.lookup(base: '勉強する');
      expect(hit, isNotNull);
      expect(hit!.level, jlpt.lookup(base: '勉強')!.level);
    });

    test('productive noun suffixes are stripped', () {
      expect(jlpt.lookup(base: '経済的'), isNotNull);
    });
  });

  group('kanji estimation', () {
    test('an unlisted compound is estimated from its hardest kanji', () {
      // Not a JLPT entry, but every kanji in it is attested.
      final hit = jlpt.estimate(base: '経済成長');
      expect(hit, isNotNull);
      expect(hit!.approximate, isTrue);
      expect(hit.level, inInclusiveRange(1, 5));
      // Never easier than the hardest character it contains.
      final kei = jlpt.lookup(base: '経済')!.level;
      expect(hit.level, lessThanOrEqualTo(kei));
    });

    test('estimation never overrides an exact listing', () {
      final exact = jlpt.lookup(base: '学校')!;
      final est = jlpt.estimate(base: '学校')!;
      expect(est.approximate, isFalse);
      expect(est.level, exact.level);
    });

    test('long katakana loanwords get an approximate intermediate level', () {
      final hit = jlpt.estimate(base: 'インフラストラクチャー');
      expect(hit, isNotNull);
      expect(hit!.approximate, isTrue);
    });

    test('bare kana with no listing stays uncoloured', () {
      expect(jlpt.estimate(base: 'ぬぬぬ'), isNull);
    });

    test('covers the overwhelming majority of kanji words in news prose', () {
      // A sample of the kind of vocabulary NHK / Mainichi headlines use, most
      // of it outside the 8k JLPT list.
      const sample = [
        '政府', '記者会見', '感染者', '経済対策', '首相', '発表', '被害',
        '地震', '気象庁', '避難', '自治体', '観光客', '物価', '賃上げ',
        '選挙', '調査', '企業', 'технолог', '国際',
      ];
      var covered = 0;
      for (final w in sample) {
        if (jlpt.estimate(base: w) != null) covered++;
      }
      // Every entry but the deliberate non-Japanese control should resolve.
      expect(covered, sample.length - 1);
    });
  });

  group('register', () {
    test('Jisho-sourced levels merge in and feed later estimates', () {
      final fresh = buildLookup();
      expect(fresh.lookup(base: '朧月夜'), isNull);
      fresh.register([(key: '朧月夜', level: 1, gloss: 'hazy moonlit night')]);
      final hit = fresh.lookup(base: '朧月夜');
      expect(hit, isNotNull);
      expect(hit!.level, 1);
      expect(hit.approximate, isFalse);
    });
  });
}
