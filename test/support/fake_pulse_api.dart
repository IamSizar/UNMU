// =============================================================================
// fake_pulse_api.dart — a scriptable stand-in for the Pulse backend, shared by
// the controller and widget tests. Every call is recorded so tests can assert
// what the app asked for; results are plain fields tests overwrite.
// =============================================================================
import 'dart:async';

import 'package:halalstocks/models/pulse_item.dart';
import 'package:halalstocks/services/pulse_service.dart';

/// A scriptable stand-in for the backend. Every call is recorded so tests can
/// assert what the controller asked for.
class FakePulseApi implements PulseApi {
  PulseResult<PulseDay> todayResult = PulseResult.ok(
    fakePulseDay([fakePulseItem(1, PulseSlot.global)]),
  );
  PulseResult<PulsePage> savedResult = PulseResult.ok(
    const PulsePage(items: [], hasMore: false),
  );
  bool saveOk = true;
  bool unsaveOk = true;

  final List<String> events = [];
  final List<String> calls = [];

  /// When true, today() calls wait until the test completes them (in call
  /// order) via [heldToday], so tests can interleave slow replies.
  bool holdToday = false;
  final List<Completer<PulseResult<PulseDay>>> heldToday = [];

  /// When true, save()/unsave() wait for the test via [heldSaves].
  bool holdSaves = false;
  final List<Completer<bool>> heldSaves = [];

  /// When set, saved() waits until the test completes it.
  Completer<void>? savedGate;

  @override
  Future<PulseResult<PulseDay>> today() async {
    calls.add('today');
    if (holdToday) {
      final c = Completer<PulseResult<PulseDay>>();
      heldToday.add(c);
      return c.future;
    }
    return todayResult;
  }

  @override
  Future<PulseResult<PulseDay>> day(String date) async => todayResult;

  @override
  Future<PulseResult<PulseItem>> item(int id) async =>
      PulseResult.ok(fakePulseItem(id, PulseSlot.global));

  @override
  Future<PulseResult<PulsePage>> archive({
    String? from,
    String? to,
    String? query,
    int offset = 0,
    int limit = 30,
  }) async {
    calls.add('archive from=$from to=$to q=$query offset=$offset');
    return PulseResult.ok(
      PulsePage(items: [fakePulseItem(5, PulseSlot.gulf, saved: true)], hasMore: false),
    );
  }

  @override
  Future<PulseResult<PulsePage>> saved({int offset = 0, int limit = 30}) async {
    calls.add('saved offset=$offset');
    await savedGate?.future;
    return savedResult;
  }

  @override
  Future<bool> save(int itemId) async {
    calls.add('save $itemId');
    return _held(saveOk);
  }

  @override
  Future<bool> unsave(int itemId) async {
    calls.add('unsave $itemId');
    return _held(unsaveOk);
  }

  Future<bool> _held(bool result) {
    if (!holdSaves) return Future.value(result);
    final c = Completer<bool>();
    heldSaves.add(c);
    return c.future;
  }

  @override
  Future<void> recordEvent(String event, {int? itemId}) async {
    events.add('$event:${itemId ?? '-'}');
  }
}

PulseItem fakePulseItem(int id, PulseSlot slot, {bool saved = false}) => PulseItem(
  id: id,
  date: '2026-10-22',
  slot: slot,
  isAnalysis: false,
  titleAr: 'عنوان $id',
  titleEn: 'Title $id',
  summaryAr: 'ملخص',
  summaryEn: 'Summary',
  isSaved: saved,
);

PulseDay fakePulseDay(List<PulseItem> items) =>
    PulseDay(date: '2026-10-22', items: items);

