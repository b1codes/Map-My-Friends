import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/models/person.dart';

void main() {
  group('Person Model Serialization Fix', () {
    test('toJson should use "tag" key instead of "relationship_tag"', () {
      final person = Person(
        id: '1',
        firstName: 'John',
        lastName: 'Doe',
        relationshipTag: 'FRIEND',
        city: 'NY',
        state: 'NY',
        country: 'USA',
      );

      final json = person.toJson();

      expect(
        json.containsKey('tag'),
        isTrue,
        reason: 'JSON should contain key "tag"',
      );
      expect(
        json.containsKey('relationship_tag'),
        isFalse,
        reason: 'JSON should NOT contain key "relationship_tag"',
      );
      expect(json['tag'], 'FRIEND');
    });

    test('fromJson should populate from "tag" key', () {
      final json = {
        'id': '1',
        'first_name': 'Jane',
        'last_name': 'Doe',
        'tag': 'FAMILY',
        'city': 'LA',
        'state': 'CA',
        'country': 'USA',
      };

      final person = Person.fromJson(json);

      expect(person.relationshipTag, 'FAMILY');
    });
  });
}
