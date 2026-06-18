import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'connection_profile.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient(ConnectionProfile profile)
      : _profile = profile,
        _dio = Dio(
          BaseOptions(
            baseUrl: profile.apiBaseUrl,
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 30),
            sendTimeout: const Duration(seconds: 30),
            responseType: ResponseType.json,
          ),
        ) {
    _dio.options.headers.addAll(profile.activeHeaders);
    if (profile.token.isNotEmpty) {
      _dio.options.headers['Authorization'] = 'Bearer ${profile.token}';
    }
  }

  final ConnectionProfile _profile;
  final Dio _dio;

  ConnectionProfile get profile => _profile;

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    return _request(() => _dio.get<dynamic>(path, queryParameters: query));
  }

  Future<dynamic> post(String path, {Object? data}) async {
    return _request(() => _dio.post<dynamic>(path, data: data));
  }

  Future<dynamic> patch(String path, {Object? data}) async {
    return _request(() => _dio.patch<dynamic>(path, data: data));
  }

  Future<dynamic> delete(String path, {Object? data}) async {
    return _request(() => _dio.delete<dynamic>(path, data: data));
  }

  Future<Uint8List> download(String path, {Map<String, dynamic>? query}) async {
    try {
      final response = await _dio.get<List<int>>(
        path,
        queryParameters: query,
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(response.data ?? const []);
    } on DioException catch (error) {
      throw _fromDio(error);
    }
  }

  Future<dynamic> uploadDatabase(String path, String filePath) async {
    final form = FormData.fromMap({
      'db': await MultipartFile.fromFile(filePath, filename: 's-ui.db'),
    });
    return _request(() => _dio.post<dynamic>(path, data: form));
  }

  Future<dynamic> _request(Future<Response<dynamic>> Function() call) async {
    try {
      final response = await call();
      final body = response.data;
      if (body is Map) {
        if (body['success'] == true) return body['data'];
        if (body['success'] == false) {
          throw ApiException(
            body['error']?.toString() ?? body['msg']?.toString() ?? '请求失败',
            statusCode: response.statusCode,
          );
        }
      }
      return body;
    } on ApiException {
      rethrow;
    } on DioException catch (error) {
      throw _fromDio(error);
    }
  }

  ApiException _fromDio(DioException error) {
    final data = error.response?.data;
    String? message;
    if (data is Map) {
      message = data['error']?.toString() ?? data['msg']?.toString();
    }
    message ??= switch (error.type) {
      DioExceptionType.connectionTimeout => '连接超时，请检查地址与网络',
      DioExceptionType.connectionError => '无法连接面板，请检查地址、证书与自定义 Header',
      DioExceptionType.badCertificate => '面板 TLS 证书无效',
      DioExceptionType.receiveTimeout => '面板响应超时',
      _ => error.message ?? '网络请求失败',
    };
    return ApiException(message, statusCode: error.response?.statusCode);
  }

  static Future<Map<String, dynamic>> login({
    required ConnectionProfile profile,
    required String username,
    required String password,
    String code = '',
    int expiryDays = 30,
  }) async {
    final client = ApiClient(profile.copyWith(token: ''));
    final result = await client.post('auth/login', data: {
      'username': username,
      'password': password,
	  if (code.trim().isNotEmpty) 'code': code.trim(),
      'expiryDays': expiryDays,
    });
    return Map<String, dynamic>.from(result as Map);
  }
}
