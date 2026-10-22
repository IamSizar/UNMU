import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:halalstocks/controllers/pulse_controller.dart';
import 'package:halalstocks/models/pulse_item.dart';
import 'package:halalstocks/services/pulse_service.dart';
import '../support/fake_pulse_api.dart';

void main() {
  late FakePulseApi api;
  late PulseController c;

  setUp(() {
    Get.reset();
    api = FakePulseApi();
    c = PulseController(api: api);
  });

  group('loading today', () {
    test('success fills the day and clears any failure', () async {
      await c.loadToday();
      expect(c.day.value?.items.length, 1);
      expect(c.failure.value, isNull);
      expect(c.loading.value, isFalse);
      expect(c.refreshFailed, isFalse);
    });

    test('first-load failure leaves no content and records why', () async {
      api.todayResult = const PulseResult.fail(PulseFailure.offline);
      await c.loadToday();
      expect(c.day.value, isNull);
      expect(c.failure.value, PulseFailure.offline);
      expect(
        c.refreshFailed,
        isFalse,
      ); // nothing stale to show: a full error state
    });

    test(
      'a failed refresh keeps the last content visible and flags it',
      () async {
        await c.loadToday();
        api.todayResult = const PulseResult.fail(PulseFailure.server);
        await c.refreshToday();
        expect(c.day.value?.items.length, 1); // still on screen
        expect(c.refreshFailed, isTrue);
      },
    );

    test('a later success clears the failure', () async {
      api.todayResult = const PulseResult.fail(PulseFailure.server);
      await c.loadToday();
      api.todayResult = PulseResult.ok(fakePulseDay([fakePulseItem(1, PulseSlot.global)]));
      await c.loadToday();
      expect(c.failure.value, isNull);
    });

    test('an empty day is a success, not an error', () async {
      api.todayResult = PulseResult.ok(fakePulseDay([]));
      await c.loadToday();
      expect(c.failure.value, isNull);
      expect(c.day.value!.isEmpty, isTrue);
    });
  });

  group('saving', () {
    test('items the server says are saved are remembered', () async {
      api.todayResult = PulseResult.ok(
        fakePulseDay([
          fakePulseItem(1, PulseSlot.global, saved: true),
          fakePulseItem(2, PulseSlot.gulf),
        ]),
      );
      await c.loadToday();
      expect(c.isSaved(1), isTrue);
      expect(c.isSaved(2), isFalse);
    });

    test('toggle flips the state and tells the server', () async {
      await c.loadToday();
      final item = c.day.value!.items.first;

      expect(await c.toggleSave(item), isTrue);
      expect(c.isSaved(item.id), isTrue);
      expect(api.calls, contains('save 1'));

      expect(await c.toggleSave(item), isFalse);
      expect(c.isSaved(item.id), isFalse);
      expect(api.calls, contains('unsave 1'));
    });

    test('a refused save is rolled back', () async {
      await c.loadToday();
      final item = c.day.value!.items.first;
      api.saveOk = false;

      expect(await c.toggleSave(item), isFalse);
      expect(c.isSaved(item.id), isFalse);
      expect(
        api.events,
        isEmpty,
      ); // no analytics for something that did not happen
    });

    test('a refused unsave is rolled back', () async {
      api.todayResult = PulseResult.ok(
        fakePulseDay([fakePulseItem(1, PulseSlot.global, saved: true)]),
      );
      await c.loadToday();
      api.unsaveOk = false;

      expect(await c.toggleSave(c.day.value!.items.first), isTrue);
      expect(c.isSaved(1), isTrue);
    });

    test('unsaving removes the item from the loaded saved list', () async {
      api.savedResult = PulseResult.ok(
        PulsePage(
          items: [
            fakePulseItem(1, PulseSlot.global, saved: true),
            fakePulseItem(2, PulseSlot.gulf, saved: true),
          ],
          hasMore: false,
        ),
      );
      await c.loadSaved();
      expect(c.savedItems.length, 2);

      await c.toggleSave(c.savedItems.first);
      expect(c.savedItems.map((i) => i.id), [2]);
    });

    test(
      'saving an item adds it to the top of an already-loaded saved list',
      () async {
        await c.loadSaved(); // empty list loaded
        final item = fakePulseItem(9, PulseSlot.opportunity);
        await c.toggleSave(item);
        expect(c.savedItems.first.id, 9);
        expect(c.savedItems.first.isSaved, isTrue);
      },
    );

    test('a failed saved-list load records the reason', () async {
      api.savedResult = const PulseResult.fail(PulseFailure.offline);
      await c.loadSaved();
      expect(c.savedFailure.value, PulseFailure.offline);
    });
  });

  group('archive', () {
    test('passes the filters through and remembers saved ids', () async {
      final res = await c.loadArchive(
        from: '2026-10-01',
        to: '2026-10-22',
        query: 'bank',
        offset: 30,
      );
      expect(res.ok, isTrue);
      expect(
        api.calls.last,
        'archive from=2026-10-01 to=2026-10-22 q=bank offset=30',
      );
      expect(c.isSaved(5), isTrue); // the archive item came back saved
    });
  });

  group('analytics', () {
    test('events are sent', () {
      c.track(PulseEvent.openItem, itemId: 3);
      expect(api.events, ['open_item:3']);
    });

    test('"once" events are not repeated for the same item', () {
      c.track(PulseEvent.readComplete, itemId: 3, once: true);
      c.track(PulseEvent.readComplete, itemId: 3, once: true);
      c.track(PulseEvent.readComplete, itemId: 4, once: true);
      expect(api.events, ['read_complete:3', 'read_complete:4']);
    });

    test('the day view is counted once per day', () {
      c.trackDayViewed('2026-10-22');
      c.trackDayViewed('2026-10-22');
      c.trackDayViewed('2026-10-23');
      expect(api.events, ['view_day:-', 'view_day:-']);
    });
  });
}
