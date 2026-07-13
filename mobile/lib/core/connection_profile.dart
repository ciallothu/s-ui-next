import 'dart:convert';

class ConnectionProfile {
  const ConnectionProfile({
    this.id = '',
    required this.name,
    required this.baseUrl,
    this.token = '',
    this.headers = const {},
  });

  final String id;
  final String name;
  final String baseUrl;
  final String token;
  final Map<String, String> headers;

  static const cloudflareClientId = 'CF-Access-Client-Id';
  static const cloudflareClientSecret = 'CF-Access-Client-Secret';

  factory ConnectionProfile.empty() => const ConnectionProfile(
        name: 'S-UI Next',
        baseUrl: '',
        headers: {
          cloudflareClientId: '',
          cloudflareClientSecret: '',
        },
      );

  String get normalizedBaseUrl {
    var value = baseUrl.trim();
    if (value.isEmpty) return value;
    if (!value.endsWith('/')) value = '$value/';
    return value;
  }

  String get apiBaseUrl => '${normalizedBaseUrl}apiv3/';

  bool get hasValidBaseUrl {
    final uri = Uri.tryParse(normalizedBaseUrl);
    if (uri == null) return false;
    final scheme = uri.scheme.toLowerCase();
    return (scheme == 'http' || scheme == 'https') &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        uri.query.isEmpty &&
        uri.fragment.isEmpty;
  }

  Map<String, String> get activeHeaders => Map.fromEntries(
        headers.entries.where(
          (entry) => entry.key.trim().isNotEmpty && entry.value.trim().isNotEmpty,
        ),
      );

  ConnectionProfile copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? token,
    Map<String, String>? headers,
  }) =>
      ConnectionProfile(
        id: id ?? this.id,
        name: name ?? this.name,
        baseUrl: baseUrl ?? this.baseUrl,
        token: token ?? this.token,
        headers: headers ?? this.headers,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': normalizedBaseUrl,
        'token': token,
        'headers': headers,
      };

  factory ConnectionProfile.fromJson(Map<String, dynamic> json) {
    final rawHeaders = json['headers'];
    final headers = <String, String>{
      cloudflareClientId: '',
      cloudflareClientSecret: '',
    };
    if (rawHeaders is Map) {
      for (final entry in rawHeaders.entries) {
        headers[entry.key.toString()] = entry.value?.toString() ?? '';
      }
    }
    return ConnectionProfile(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'S-UI Next',
      baseUrl: json['baseUrl']?.toString() ?? '',
      token: json['token']?.toString() ?? '',
      headers: headers,
    );
  }

  String encode() => jsonEncode(toJson());

  factory ConnectionProfile.decode(String value) =>
      ConnectionProfile.fromJson(jsonDecode(value) as Map<String, dynamic>);
}
