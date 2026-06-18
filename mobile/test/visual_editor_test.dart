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

  test('renaming a client updates protocol identities', () {
    final schema = VisualEditorSchema.forResource('clients');
    final client = schema.defaultValue() as Map<String, dynamic>;

    schema.syncClientName(client, 'new-user');

    expect((client['config'] as Map)['mixed']['username'], 'new-user');
    expect((client['config'] as Map)['vless']['name'], 'new-user');
  });
}
