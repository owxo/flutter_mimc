import 'dart:convert';

import 'package:http/http.dart' as http;

final class MimcTokenClient {
  const MimcTokenClient({
    required this.endpoint,
    this.userToken = '',
    this.testAuthToken = '',
  }) : assert(userToken == '' || testAuthToken == '');

  final String endpoint;
  final String userToken;
  final String testAuthToken;

  /// [appAccount] is sent only by the explicitly authenticated local E2E mode.
  /// Production FastAdmin resolves it from the `token` header instead.
  Future<String> fetchForAccount(String appAccount) async {
    final Uri? uri = Uri.tryParse(endpoint);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw StateError('Invalid MIMC token endpoint: $endpoint');
    }

    final Map<String, String> headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json; charset=UTF-8',
      if (userToken.isNotEmpty) 'token': userToken,
      if (testAuthToken.isNotEmpty) 'Authorization': 'Bearer $testAuthToken',
    };
    final http.Response response = await http
        .post(
          uri,
          headers: headers,
          body: jsonEncode(<String, String>{
            if (testAuthToken.isNotEmpty) 'appAccount': appAccount,
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw StateError(
        'Token endpoint returned HTTP ${response.statusCode}: '
        '${response.body}',
      );
    }

    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['code'] != 200) {
      throw StateError('Token endpoint rejected the request: ${response.body}');
    }
    final Object? data = decoded['data'];
    if (data is! Map || data['token'] is! String) {
      throw StateError('Token endpoint response does not contain data.token');
    }
    if ('${data['appAccount'] ?? ''}' != appAccount) {
      throw StateError(
        'Token account ${data['appAccount']} does not match $appAccount',
      );
    }

    // Native and Web SDKs consume the complete Xiaomi response, not data.token.
    return response.body;
  }
}
