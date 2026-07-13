import 'package:flutter_test/flutter_test.dart';
import 'package:sui_mobile/core/connection_profile.dart';

void main() {
  test('normalizes panel web path and API base URL', () {
    const profile = ConnectionProfile(
      name: 'test',
      baseUrl: 'https://panel.example.com/app',
      token: 'secret',
    );
    expect(profile.normalizedBaseUrl, 'https://panel.example.com/app/');
    expect(profile.apiBaseUrl, 'https://panel.example.com/app/apiv3/');
  });

  test('keeps only non-empty custom headers', () {
    const profile = ConnectionProfile(
      name: 'test',
      baseUrl: 'https://panel.example.com/',
      headers: {
        ConnectionProfile.cloudflareClientId: 'client-id',
        ConnectionProfile.cloudflareClientSecret: '',
        'X-Custom': 'value',
      },
    );
    expect(profile.activeHeaders, {
      ConnectionProfile.cloudflareClientId: 'client-id',
      'X-Custom': 'value',
    });
  });

  test('accepts only HTTP panel URLs without embedded credentials or query data', () {
    const validHttps = ConnectionProfile(name: 'https', baseUrl: 'https://panel.example.com/app');
    const validHttp = ConnectionProfile(name: 'http', baseUrl: 'http://192.0.2.10:2095/app/');
    const invalidScheme = ConnectionProfile(name: 'file', baseUrl: 'file:///tmp/panel');
    const embeddedCredentials = ConnectionProfile(name: 'credentials', baseUrl: 'https://admin:secret@panel.example.com/app/');
    const query = ConnectionProfile(name: 'query', baseUrl: 'https://panel.example.com/app/?token=secret');

    expect(validHttps.hasValidBaseUrl, isTrue);
    expect(validHttp.hasValidBaseUrl, isTrue);
    expect(invalidScheme.hasValidBaseUrl, isFalse);
    expect(embeddedCredentials.hasValidBaseUrl, isFalse);
    expect(query.hasValidBaseUrl, isFalse);
  });

  test('round-trips secure profile JSON', () {
    const profile = ConnectionProfile(
      id: 'panel-1',
      name: 'panel',
      baseUrl: 'https://panel.example.com/',
      token: 'token',
      headers: {'X-Test': 'ok'},
    );
    final decoded = ConnectionProfile.decode(profile.encode());
    expect(decoded.id, profile.id);
    expect(decoded.name, profile.name);
    expect(decoded.token, profile.token);
    expect(decoded.headers['X-Test'], 'ok');
    expect(decoded.headers, contains(ConnectionProfile.cloudflareClientId));
  });

  test('decodes legacy profile JSON without an id', () {
    final decoded = ConnectionProfile.decode(
      '{"name":"legacy","baseUrl":"https://panel.example.com/","token":"token"}',
    );
    expect(decoded.id, isEmpty);
    expect(decoded.name, 'legacy');
    expect(decoded.token, 'token');
  });
}
