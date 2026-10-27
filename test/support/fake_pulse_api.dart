// =============================================================================
// fake_pulse_api.dart — a scriptable stand-in for the Pulse backend, shared by
// the controller and widget tests. Every call is recorded so tests can assert
// what the app asked for; results are plain fields tests overwrite.
// =============================================================================
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

  @override
  Future<PulseResult<PulseDay>> today() async {
    calls.add('today');
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
    return savedResult;
  }

  @override
  Future<bool> save(int itemId) async {
    calls.add('save $itemId');
    return saveOk;
  }

  @override
  Future<bool> unsave(int itemId) async {
    calls.add('unsave $itemId');
    return unsaveOk;
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

