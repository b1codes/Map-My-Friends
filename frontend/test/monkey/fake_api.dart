import 'dart:convert';
import 'dart:math';

import 'package:map_my_friends/services/api_config.dart';

import '../contracts/contract_support.dart';
import '../helpers/recording_http_overrides.dart';

/// A stateful, in-memory stand-in for the whole network the app talks to:
/// the API, OSRM, map tiles and profile photos.
///
/// Every reply is built from the contract examples in `contracts/` (the
/// shapes the Django provider tests hold the real API to), with the account's
/// data kept here, so adding a friend, logging a contact or saving a trip
/// changes what the next list returns. That's what lets a monkey wander
/// through real flows rather than bouncing off empty screens.
///
/// Install [respond] as a [RecordingHttpOverrides.responder].
class FakeApi {
  FakeApi({int people = 6, this.random}) {
    for (var i = 0; i < people; i++) {
      _addPerson(_seedPeople[i % _seedPeople.length], at: i);
    }
    _logs.add({
      ...(_example('contact_logs.create') as Map<String, dynamic>),
      'id': _newId(),
      'person': _people.keys.first,
    });
    _trips[_tripId] = _savedTrip(_tripId, {
      ...(apiInteractions['trips.create']!.request['json']
          as Map<String, dynamic>),
      'stops': [
        for (final (i, id) in _people.keys.take(2).indexed)
          {
            'people': [id],
            'airport': null,
            'station': null,
            'sequence_order': i,
            'location': _people[id]!['geometry'],
          },
      ],
    });
  }

  /// Draws the ids new records get. Seeded from the monkey's seed, so a run
  /// replays with the same ids.
  final Random? random;

  /// The access and refresh tokens a stored login holds at launch.
  static const accessToken = 'monkey-access-token';
  static const refreshToken = 'monkey-refresh-token';

  final Set<String> _issuedAccess = {accessToken};
  int _rotations = 0;

  /// people/ features by id, in insertion order (the API's order).
  final Map<String, Map<String, dynamic>> _people = {};
  final List<Map<String, dynamic>> _logs = [];
  final Map<String, Map<String, dynamic>> _trips = {};
  final String _tripId = 'monkey-trip-0';

  Map<String, dynamic> _profile = Map.of(
    _example('profile.get') as Map<String, dynamic>,
  );

  /// Requests no route here answers. A monkey run fails if any appear: the
  /// app asked for something the API doesn't have.
  final List<String> unknownRoutes = [];

  static final Uri _api = Uri.parse(ApiConfig.baseUrl);

  static dynamic _example(String id) =>
      jsonDecode(jsonEncode(apiInteractions[id]!.example));

  CannedResponse respond(RecordedRequest request) {
    final uri = request.uri;
    if (uri.host == _api.host && uri.port == _api.port) {
      return _respondApi(request, uri.path.substring(_api.path.length));
    }
    if (uri.host == Uri.parse(ApiConfig.osrmBaseUrl).host) {
      return CannedResponse.json(200, _osrmRoute);
    }
    // Map tiles, and profile photos wherever the API says they live.
    return CannedResponse(200, transparentPng, const {
      'content-type': ['image/png'],
      'cache-control': ['max-age=60'],
      'date': ['Thu, 05 Mar 2026 00:00:00 GMT'],
    });
  }

  CannedResponse _respondApi(RecordedRequest r, String path) {
    final key = '${r.method} $path';
    if (path.startsWith('user/auth/')) return _auth(r, path);

    final auth = r.headers['authorization']?.join();
    final token = auth != null && auth.startsWith('Bearer ')
        ? auth.substring('Bearer '.length)
        : null;
    if (token == null || !_issuedAccess.contains(token)) {
      return CannedResponse.json(401, _example('auth.token.not_valid'));
    }

    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    final collection = segments.isEmpty ? '' : segments.first;
    final id = segments.length > 1 ? segments[1] : null;

    switch ((r.method, collection, id)) {
      case ('GET', 'user', _) when path == 'user/profile/':
        return CannedResponse.json(200, _profile);
      case ('PATCH', 'user', _) when path == 'user/profile/':
        return _updateProfile(r);

      case ('GET', 'people', null):
        return CannedResponse.json(200, {
          'type': 'FeatureCollection',
          'features': _people.values.toList(),
        });
      case ('POST', 'people', null):
        final fields = _formFields(r);
        if ((fields['first_name'] ?? '').isEmpty) {
          return CannedResponse.json(400, {
            'first_name': ['This field may not be blank.'],
          });
        }
        return CannedResponse.json(201, _addPerson(fields));
      case ('PATCH' || 'PUT', 'people', final String id):
        final person = _people[id];
        if (person == null) return _notFound;
        _applyPersonFields(person, _formFields(r));
        return CannedResponse.json(200, person);
      case ('DELETE', 'people', final String id):
        if (_people.remove(id) == null) return _notFound;
        _logs.removeWhere((l) => l['person'] == id);
        return const CannedResponse(204, []);

      case ('GET', 'contact-logs', null):
        final person = r.uri.queryParameters['person'];
        return CannedResponse.json(200, [
          for (final log in _logs.reversed)
            if (person == null || log['person'] == person) log,
        ]);
      case ('POST', 'contact-logs', null):
        final body = _json(r);
        final person = _people[body['person']];
        if (person == null) {
          return CannedResponse.json(400, {
            'person': ['Invalid pk - object does not exist.'],
          });
        }
        final log = {
          'id': _newId(),
          'person': body['person'],
          'channel': body['channel'] ?? 'CALL',
          'contacted_at': body['contacted_at'],
          'note': body['note'] ?? '',
          'created_at': '2026-03-05T12:00:00+00:00',
        };
        _logs.add(log);
        (person['properties'] as Map<String, dynamic>)
          ..['last_contacted_at'] = body['contacted_at']
          ..['last_contact_channel'] = log['channel'];
        return CannedResponse.json(201, log);

      case ('GET', 'trips', null):
        return CannedResponse.json(200, _trips.values.toList());
      case ('POST', 'trips', null):
        final tripId = _newId();
        return CannedResponse.json(
          201,
          _trips[tripId] = _savedTrip(tripId, _json(r)),
        );
      case ('PATCH' || 'PUT', 'trips', final String id):
        final old = _trips[id];
        if (old == null) return _notFound;
        return CannedResponse.json(
          200,
          _trips[id] = _savedTrip(id, {...old, ..._json(r)}),
        );
      case ('DELETE', 'trips', final String id):
        return _trips.remove(id) == null
            ? _notFound
            : const CannedResponse(204, []);

      case ('GET', 'airports', 'nearest'):
        return CannedResponse.json(200, _example('airports.nearest'));
      case ('GET', 'stations', 'nearest'):
        return CannedResponse.json(200, _example('stations.nearest'));
    }
    unknownRoutes.add(key);
    return _notFound;
  }

  static final _notFound = CannedResponse.json(404, {'detail': 'Not found.'});

  static final Map<String, dynamic> _user =
      contractFixtures['user'] as Map<String, dynamic>;

  CannedResponse _auth(RecordedRequest r, String path) {
    final body = r.method == 'POST' ? _json(r) : const <String, dynamic>{};
    switch (path) {
      case 'user/auth/token/':
        // The fixtures user or the dev user, as the seeded backend has.
        final ok =
            (body['username'] == _user['username'] &&
                body['password'] == _user['password']) ||
            (body['username'] == ApiConfig.devUsername &&
                body['password'] == ApiConfig.devPassword);
        if (!ok) {
          return CannedResponse.json(401, _example('auth.token.invalid'));
        }
        return CannedResponse.json(200, _issueTokens());
      case 'user/auth/token/refresh/':
        if ((body['refresh'] as String?)?.isEmpty ?? true) {
          return CannedResponse.json(401, _example('auth.token.invalid'));
        }
        return CannedResponse.json(200, _issueTokens());
      case 'user/auth/register/':
        final missing = [
          for (final field in ['username', 'email', 'password'])
            if ((body[field] as String?)?.isEmpty ?? true) field,
        ];
        if (missing.isNotEmpty) {
          return CannedResponse.json(400, {
            for (final f in missing) f: ['This field may not be blank.'],
          });
        }
        if (body['username'] == _user['username']) {
          return CannedResponse.json(400, _example('auth.register.invalid'));
        }
        return CannedResponse.json(201, {
          for (final f in ['username', 'email', 'first_name', 'last_name'])
            f: body[f] ?? '',
        });
      case 'user/auth/password-reset/':
        return CannedResponse.json(200, _example('auth.password_reset'));
    }
    unknownRoutes.add('${r.method} $path');
    return _notFound;
  }

  Map<String, String> _issueTokens() {
    final access = 'monkey-access-${++_rotations}';
    _issuedAccess.add(access);
    return {'access': access, 'refresh': 'monkey-refresh-$_rotations'};
  }

  CannedResponse _updateProfile(RecordedRequest r) {
    if (_isMultipart(r)) {
      _profile = {
        ..._profile,
        'profile_image': 'http://localhost:8000/media/user_profiles/me.png',
      };
    } else {
      final body = _json(r);
      _profile = {
        ..._profile,
        for (final e in body.entries)
          if (_profile.containsKey(e.key)) e.key: e.value,
      };
    }
    return CannedResponse.json(200, _profile);
  }

  Map<String, dynamic> _addPerson(Map<String, String> fields, {int? at}) {
    final template = _example('people.create') as Map<String, dynamic>;
    final id = at == null ? _newId() : 'monkey-person-$at';
    final person = {
      ...template,
      'id': id,
      'geometry': {
        'type': 'Point',
        // Spread the seeded people out, so the map has pins and clusters.
        'coordinates': [-87.9 + (at ?? _people.length) * 0.7, 43.0],
      },
    };
    (person['properties'] as Map<String, dynamic>)
      ..['profile_image'] = null
      ..['last_contacted_at'] = null
      ..['last_contact_channel'] = null;
    _applyPersonFields(person, fields);
    return _people[id] = person;
  }

  static void _applyPersonFields(
    Map<String, dynamic> person,
    Map<String, String> fields,
  ) {
    final props = person['properties'] as Map<String, dynamic>;
    for (final MapEntry(:key, :value) in fields.entries) {
      props[key] = switch (key) {
        'preferred_airport' ||
        'preferred_station' ||
        'contact_cadence_days' => int.tryParse(value),
        'birthday' => value.isEmpty ? null : value.split('T').first,
        _ => value,
      };
    }
    if (props['preferred_airport'] == null) {
      props['preferred_airport_detail'] = null;
    }
    if (props['preferred_station'] == null) {
      props['preferred_station_detail'] = null;
    }
  }

  Map<String, dynamic> _savedTrip(String id, Map<String, dynamic> body) {
    final template = _example('trips.create') as Map<String, dynamic>;
    final airportTemplate =
        ((template['stops'] as List)[1] as Map)['airport_detail'] as Map;
    final stopIds = <String>[];
    final stops = [
      for (final (i, stop) in ((body['stops'] as List?) ?? const []).indexed)
        () {
          final s = Map<String, dynamic>.from(stop as Map);
          final stopId = (s['id'] as String?) ?? '$id-stop-$i';
          stopIds.add(stopId);
          final people = [
            for (final p in (s['people'] as List?) ?? const [])
              if (_people.containsKey(p)) p as String,
          ];
          return {
            'id': stopId,
            'trip': id,
            'sequence_order': s['sequence_order'] ?? i,
            'location': s['location'],
            'people': people,
            'airport': s['airport'],
            'station': s['station'],
            'snapshot_address': s['snapshot_address'] ?? '',
            'snapshot_metadata': s['snapshot_metadata'] ?? <String, dynamic>{},
            'people_detail': [for (final p in people) _personDetail(p)],
            'airport_detail': s['airport'] == null
                ? null
                : {...airportTemplate, 'id': s['airport']},
            'station_detail': null,
          };
        }(),
    ];
    final legs = [
      for (final (i, leg) in ((body['legs'] as List?) ?? const []).indexed)
        {
          ...Map<String, dynamic>.from(leg as Map),
          'id': (leg['id'] as String?) ?? '$id-leg-$i',
          'trip': id,
        },
    ];
    return {
      'id': id,
      'name': body['name'] ?? '',
      'date': body['date'],
      'start_date': body['start_date'],
      'end_date': body['end_date'],
      'status': body['status'] ?? 'DRAFT',
      'user': _profile['username'],
      'stops': stops,
      'legs': [
        for (final leg in legs)
          if (stopIds.contains(leg['departure_stop']) &&
              stopIds.contains(leg['arrival_stop']))
            leg,
      ],
    };
  }

  /// A stop's `people_detail` entry: the person flattened, as the API's
  /// trip serializer writes it.
  Map<String, dynamic> _personDetail(String id) {
    final person = _people[id]!;
    final props = Map<String, dynamic>.from(person['properties'] as Map);
    final coords = (person['geometry'] as Map)['coordinates'] as List;
    final firstStop =
        ((_example('trips.create') as Map)['stops'] as List).first as Map;
    final template = firstStop['people_detail'] as List;
    return {
      for (final k in (template.first as Map<String, dynamic>).keys)
        k: switch (k) {
          'id' => id,
          'latitude' => coords[1],
          'longitude' => coords[0],
          _ => props[k],
        },
    };
  }

  String _newId() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final rng = random ?? Random(_people.length + _logs.length + _trips.length);
    return List.generate(20, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  static Map<String, dynamic> _json(RecordedRequest r) {
    if (r.body.isEmpty) return {};
    final decoded = jsonDecode(r.bodyText);
    return decoded is Map<String, dynamic> ? decoded : {};
  }

  static bool _isMultipart(RecordedRequest r) =>
      (r.headers['content-type']?.join() ?? '').startsWith('multipart/');

  /// The text fields of a multipart body (Dio's FormData). Files are
  /// recognised and skipped.
  static Map<String, String> _formFields(RecordedRequest r) {
    final type = r.headers['content-type']?.join() ?? '';
    final boundary = RegExp(r'boundary=(.+)$').firstMatch(type)?.group(1);
    if (boundary == null) return {};
    final fields = <String, String>{};
    for (final part in r.bodyText.split('--$boundary')) {
      final split = part.indexOf('\r\n\r\n');
      if (split < 0) continue;
      final head = part.substring(0, split);
      if (head.contains('filename=')) continue;
      final name = RegExp('name="([^"]*)"').firstMatch(head)?.group(1);
      if (name == null) continue;
      var value = part.substring(split + 4);
      if (value.endsWith('\r\n')) {
        value = value.substring(0, value.length - 2);
      }
      fields[name] = value;
    }
    return fields;
  }

  static final Map<String, dynamic> _osrmRoute =
      (externalInteraction('osrm', 'route').example as Map<String, dynamic>);

  /// People the account starts with, deliberately awkward: long, emoji,
  /// right-to-left and accented names, alongside an ordinary one.
  static const _seedPeople = <Map<String, String>>[
    {'first_name': 'Grace', 'last_name': 'Hopper', 'tag': 'FRIEND'},
    {
      'first_name': 'Maximiliana-Theodora-Wilhelmina',
      'last_name': 'von Hohenzollern-Sigmaringen-Ostfriesland',
      'tag': 'FAMILY',
      'city': 'Llanfairpwllgwyngyllgogerychwyrndrobwllllantysiliogogogoch',
    },
    {'first_name': '🦄✨', 'last_name': '👩🏽‍💻', 'tag': 'FRIEND'},
    {'first_name': 'نور', 'last_name': 'الهدى', 'tag': 'FAMILY'},
    {'first_name': 'Zoë', 'last_name': "O'Brien-Ñúñez", 'tag': 'FRIEND'},
    {'first_name': '李', 'last_name': '小龍', 'tag': 'FRIEND'},
  ];
}

/// A 1×1 transparent PNG: tiles and photos load quietly.
final transparentPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);
