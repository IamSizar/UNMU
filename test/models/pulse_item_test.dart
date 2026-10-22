import 'package:flutter_test/flutter_test.dart';
import 'package:halalstocks/models/pulse_item.dart';

/// Parsing tests for the Pulse models. The JSON mirrors what
/// GET /api/pulse/today and /api/pulse/items/:id return (see
/// backend/internal/models/pulse.go).
void main() {
  Map<String, dynamic> itemJson({
    int id = 7,
    String slot = 'global',
    Map<String, dynamic> extra = const {},
  }) => {
    'id': id,
    'date': '2026-10-22',
    'slot': slot,
    'classification': 'confirmed',
    'titleAr': 'عنوان',
    'titleEn': 'Title',
    'summaryAr': 'ملخص',
    'summaryEn': 'Summary',
    'sourceName': 'Filing',
    'sourceUrl': 'https://example.com',
    'verifiedAt': '2026-10-22T09:05:00+03:00',
    'publishedAt': '2026-10-22T09:10:00+03:00',
    'lastChangedAt': null,
    'changeKind': null,
    'marker': 'new',
    'stock': null,
    'relation': null,
    'isSaved': false,
    ...extra,
  };

  group('PulseItem.tryFromJson', () {
    test('parses every field of a published item', () {
      final item = PulseItem.tryFromJson(
        itemJson(
          extra: {
            'classification': 'analysis',
            'isSaved': true,
            'relation': 'portfolio',
            'stock': {
              'id': 2,
              'ticker': '2222',
              'exchange': 'TADAWUL',
              'name': 'Aramco',
            },
          },
        ),
      )!;

      expect(item.id, 7);
      expect(item.slot, PulseSlot.global);
      expect(item.isAnalysis, isTrue);
      expect(item.isSaved, isTrue);
      expect(item.relation, 'portfolio');
      expect(item.stock?.ticker, '2222');
      expect(item.stock?.exchange, 'TADAWUL');
      expect(item.verifiedAt, isNotNull);
      expect(item.publishedAt, isNotNull);
      expect(item.isNew, isTrue);
    });

    test('confirmed is the default classification', () {
      expect(PulseItem.tryFromJson(itemJson())!.isAnalysis, isFalse);
    });

    test(
      'returns null for an unknown slot instead of showing a broken card',
      () {
        expect(PulseItem.tryFromJson(itemJson(slot: 'weather')), isNull);
      },
    );

    test('returns null when the id is missing', () {
      final json = itemJson()..remove('id');
      expect(PulseItem.tryFromJson(json), isNull);
    });

    test('tolerates missing optional fields', () {
      final item = PulseItem.tryFromJson({'id': 1, 'slot': 'gulf'})!;
      expect(item.titleEn, '');
      expect(item.stock, isNull);
      expect(item.marker, '');
      expect(item.verifiedAt, isNull);
    });

    test('ignores a malformed timestamp rather than throwing', () {
      final item = PulseItem.tryFromJson(
        itemJson(extra: {'verifiedAt': 'not a date'}),
      )!;
      expect(item.verifiedAt, isNull);
    });
  });

  group('language picking', () {
    test('uses the requested language', () {
      final item = PulseItem.tryFromJson(itemJson())!;
      expect(item.title(true), 'عنوان');
      expect(item.title(false), 'Title');
      expect(item.summary(true), 'ملخص');
    });

    test(
      'falls back to the other language when the preferred one is empty',
      () {
        final item = PulseItem.tryFromJson(
          itemJson(extra: {'titleAr': '', 'detailsEn': ''}),
        )!;
        expect(item.title(true), 'Title');
        expect(item.details(true), ''); // both empty stays empty
      },
    );
  });

  group('markers', () {
    test('corrected and updated are recognised', () {
      expect(
        PulseItem.tryFromJson(
          itemJson(extra: {'marker': 'corrected'}),
        )!.isCorrected,
        isTrue,
      );
      expect(
        PulseItem.tryFromJson(
          itemJson(extra: {'marker': 'updated'}),
        )!.isUpdated,
        isTrue,
      );
      expect(
        PulseItem.tryFromJson(itemJson(extra: {'marker': ''}))!.isNew,
        isFalse,
      );
    });
  });

  test('copyWith changes only the saved flag', () {
    final item = PulseItem.tryFromJson(itemJson())!;
    final saved = item.copyWith(isSaved: true);
    expect(saved.isSaved, isTrue);
    expect(saved.id, item.id);
    expect(saved.titleEn, item.titleEn);
    expect(item.isSaved, isFalse); // original untouched
  });

  group('PulseDay', () {
    test('sorts items into slot order and skips unknown slots', () {
      final day = PulseDay.fromJson({
        'date': '2026-10-22',
        'updatedAt': '2026-10-22T09:30:00+03:00',
        'items': [
          itemJson(id: 4, slot: 'opportunity'),
          itemJson(id: 2, slot: 'sharia'),
          itemJson(id: 9, slot: 'mystery'),
          itemJson(id: 1, slot: 'global'),
        ],
      });

      expect(day.items.map((i) => i.id), [1, 2, 4]);
      expect(day.bySlot(PulseSlot.sharia)?.id, 2);
      expect(day.bySlot(PulseSlot.gulf), isNull);
      expect(day.updatedAt, isNotNull);
      expect(day.isEmpty, isFalse);
    });

    test('an empty day is reported as empty', () {
      final day = PulseDay.fromJson({'date': '2026-10-22', 'items': []});
      expect(day.isEmpty, isTrue);
    });
  });

  test('PulsePage parses items and hasMore', () {
    final page = PulsePage.fromJson({
      'items': [itemJson(id: 1), itemJson(id: 2, slot: 'gulf')],
      'hasMore': true,
    });
    expect(page.items.length, 2);
    expect(page.hasMore, isTrue);
  });
}
