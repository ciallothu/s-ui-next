import 'dart:convert';

class ConnectionProfile {
  const ConnectionProfile({
    required this.name,
    required this.baseUrl,
    this.token = '',
    this.headers = const {},
  });

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

  Map<String, String> get activeHeaders => Map.fromEntries(
        headers.entries.where(
          (entry) => entry.key.trim().isNotEmpty && entry.value.trim().isNotEmpty,
        ),
      );

  ConnectionProfile copyWith({
    String? name,
    String? baseUrl,
    String? token,
    Map<String, String>? headers,
  }) =>
      ConnectionProfile(
        name: name ?? this.name,
        baseUrl: baseUrl ?? this.baseUrl,
        token: token ?? this.token,
        headers: headers ?? this.headers,
      );

  Map<String, dynamic> toJson() => {
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
