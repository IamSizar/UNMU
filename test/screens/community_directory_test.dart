// Communities created by admins are not in the hard-coded sample list; UI
// that only has an id must still find them through the backend.
import 'package:flutter_test/flutter_test.dart';
import 'package:halalstocks/screens/social/community_directory.dart';
import 'package:halalstocks/services/community_service.dart';

CommunityMeta _meta(String id) => CommunityMeta(
  id: id,
  name: 'Name $id',
  regionCode: 'GCC',
  tagline: 'tag',
  description: '',
  rules: '',
  coverUrl: 'https://cdn.test/$id.png',
  avatarUrl: 'https://cdn.test/$id-a.png',
  isPublic: true,
  category: '',
  tags: const [],
  memberCount: 42,
  activeNow: 3,
  ownerId: 7,
);

void main() {
  late List<String> calls;

  setUp(() {
    CommunityDirectory.clear();
    calls = [];
    CommunityDirectory.fetch = (id) async {
      calls.add(id);
      return id == 'missing' ? null : _meta(id);
    };
  });

  test('finds a community that is not in the sample data', () async {
    final c = await CommunityDirectory.find('c_admin_made');
    expect(c?.id, 'c_admin_made');
    expect(c?.name, 'Name c_admin_made');
    expect(c?.memberCount, 42);
    expect(c?.ownerId, 7);
    expect(c?.coverUrl, 'https://cdn.test/c_admin_made.png');
  });

  test('caches hits', () async {
    await CommunityDirectory.find('c1');
    await CommunityDirectory.find('c1');
    expect(calls, ['c1']);
  });

  test('misses are not cached, so a later lookup can succeed', () async {
    expect(await CommunityDirectory.find('missing'), isNull);
    expect(await CommunityDirectory.find('missing'), isNull);
    expect(calls, ['missing', 'missing']);
  });

  test('an empty id is a miss without a request', () async {
    expect(await CommunityDirectory.find(''), isNull);
    expect(calls, isEmpty);
  });
}
