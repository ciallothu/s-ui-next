String connectionEndpointTarget(Map<String, dynamic> info) {
  for (final key in const ['host', 'ip', 'address']) {
    final value = info[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return '';
}

String connectionEndpointOwnership(Map<String, dynamic> info, {String fallback = ''}) {
  final scope = info['scope']?.toString() ?? '';
  final isp = info['isp']?.toString().trim() ?? '';
  final attribution = info['attribution']?.toString().trim() ?? '';
  final location = _firstValue(info, const ['city', 'region', 'country']);
  final ip = info['ip']?.toString().trim() ?? '';
  final target = connectionEndpointTarget(info);
  final parts = <String>[];

  void add(String value) {
    value = value.trim();
    if (value.isEmpty || parts.any((item) => item.toLowerCase() == value.toLowerCase())) return;
    parts.add(value);
  }

  if (isp.isNotEmpty) {
    add(isp);
  } else if (scope != 'domain') {
    add(attribution);
  }
  add(location);
  if (ip.isNotEmpty && ip != target) add(ip);
  if (parts.isEmpty && scope != 'domain') add(fallback);
  return parts.join(' · ');
}

String connectionEndpointSummary(Map<String, dynamic> info, {String fallback = ''}) {
  final target = connectionEndpointTarget(info);
  final ownership = connectionEndpointOwnership(info, fallback: fallback);
  return [target, ownership].where((value) => value.isNotEmpty).join(' · ');
}

String? connectionLookupAddress(Map<dynamic, dynamic>? connection) {
  if (connection == null) return null;
  for (final key in const ['destination', 'source']) {
    final value = connection[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return null;
}

String? connectionInfoKey(Map<dynamic, dynamic> connection) {
  final destination = connection['destination']?.toString().trim() ?? '';
  if (destination.isNotEmpty) return 'destinationInfo';
  final source = connection['source']?.toString().trim() ?? '';
  if (source.isNotEmpty) return 'sourceInfo';
  return null;
}

bool connectionInfoComplete(Map<dynamic, dynamic> info) {
  final scope = info['scope']?.toString() ?? '';
  if (scope != 'domain' && scope != 'public') return true;
  final hasLocation = const ['city', 'region', 'country'].any((key) => info[key]?.toString().isNotEmpty == true);
  return info['ip']?.toString().isNotEmpty == true && info['isp']?.toString().isNotEmpty == true && hasLocation;
}

void applyResolvedConnectionInfo(Map<dynamic, dynamic> connection, Map<String, dynamic> info) {
  final key = connectionInfoKey(connection);
  if (key == null) return;
  connection[key] = info;
  if (key == 'destinationInfo' && connection['remote'] == connection['destination']) {
    connection['remoteInfo'] = info;
  }
}

String _firstValue(Map<String, dynamic> info, List<String> keys) {
  for (final key in keys) {
    final value = info[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return '';
}
