import 'package:flutter_test/flutter_test.dart';
import 'package:sui_mobile/core/connection_display.dart';

void main() {
  test('domain target keeps its name and shows resolved ownership', () {
    final info = <String, dynamic>{
      'host': 's-ui.routeforge.network',
      'ip': '104.21.10.20',
      'scope': 'public',
      'isp': 'Cloudflare',
      'city': 'Los Angeles',
    };

    expect(connectionEndpointTarget(info), 's-ui.routeforge.network');
    expect(connectionEndpointOwnership(info), 'Cloudflare · Los Angeles · 104.21.10.20');
  });

  test('unresolved domain does not present its type as ownership', () {
    final info = <String, dynamic>{
      'host': 'example.com',
      'scope': 'domain',
      'attribution': 'Domain name',
    };

    expect(connectionEndpointTarget(info), 'example.com');
    expect(connectionEndpointOwnership(info, fallback: 'Domain name'), isEmpty);
  });
}
