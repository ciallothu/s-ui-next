import 'package:flutter_test/flutter_test.dart';
import 'package:sui_mobile/ui/visual_editor.dart';

void main() {
  test('resource defaults include the web editor protocol fields', () {
    final client = VisualEditorSchema.forResource('clients').defaultValue() as Map<String, dynamic>;
    expect(client['name'], isNotEmpty);
    expect((client['config'] as Map).keys, containsAll(['mixed', 'shadowsocks', 'vmess', 'vless', 'tuic', 'hysteria2']));

    final inbound = VisualEditorSchema.forResource('inbounds').defaultValue() as Map<String, dynamic>;
    expect(inbound['type'], 'vless');
    expect(inbound['listen_port'], 443);
  });

  test('changing a protocol keeps resource identity and applies defaults', () {
    final schema = VisualEditorSchema.forResource('inbounds');
    final inbound = <String, dynamic>{'id': 9, 'type': 'direct', 'tag': 'entry', 'listen': '::', 'listen_port': 8443, 'tls_id': 2};

    schema.applyRootType(inbound, 'vless');

    expect(inbound['id'], 9);
    expect(inbound['tag'], 'entry');
    expect(inbound['listen_port'], 8443);
    expect(inbound['type'], 'vless');
    expect(inbound['transport'], isA<Map>());
  });

  test('endpoint type changes create safe editable templates', () {
    final schema = VisualEditorSchema.forResource('endpoints');
    final endpoint = <String, dynamic>{'id': 3, 'type': 'wireguard', 'tag': 'node-a'};

    schema.applyRootType(endpoint, 'warp');
    expect(endpoint['id'], 3);
    expect(endpoint['tag'], 'node-a');
    expect(endpoint['type'], 'warp');
    expect(endpoint['peers'], isA<List>());
    expect(endpoint['peers'], isEmpty);
    expect(endpoint['ext'], isA<Map>());
    expect(endpoint['warp_terms_accepted'], false);
    expect(endpoint['mtu'], 1280);

    schema.applyRootType(endpoint, 'tailscale');
    expect(endpoint['id'], 3);
    expect(endpoint['tag'], 'node-a');
    expect(endpoint['type'], 'tailscale');
    expect(endpoint['accept_routes'], false);
  });

  test('service type changes keep listen values and expose service fields', () {
    final schema = VisualEditorSchema.forResource('services');
    final service = <String, dynamic>{'id': 2, 'type': 'resolved', 'tag': 'svc-a', 'listen': '::', 'listen_port': 1053, 'tls_id': 7};

    schema.applyRootType(service, 'ocm');
    expect(service['id'], 2);
    expect(service['tag'], 'svc-a');
    expect(service['listen_port'], 1053);
    expect(service['tls_id'], 7);
    expect(service['credential_path'], '');
    expect(service['users'], isA<List>());

    final fields = schema.suggestedKeys('', root: service);
    expect(fields, containsAll(['credential_path', 'usages_path', 'users', 'headers', 'detour']));
  });

  test('renaming a client updates protocol identities', () {
    final schema = VisualEditorSchema.forResource('clients');
    final client = schema.defaultValue() as Map<String, dynamic>;

    schema.syncClientName(client, 'new-user');

    expect((client['config'] as Map)['mixed']['username'], 'new-user');
    expect((client['config'] as Map)['vless']['name'], 'new-user');
  });

  test('empty numeric lists keep numeric values', () {
    final schema = VisualEditorSchema.forResource('clients');
    expect(schema.parseListItem(<dynamic>[], 'inbounds', '12'), 12);
  });
}
