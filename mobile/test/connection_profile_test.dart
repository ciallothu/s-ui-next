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
