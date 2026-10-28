import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../security/secure_store.dart';

class SyncApiException implements Exception {
  const SyncApiException(this.message, {this.code, this.statusCode});

  final String message;
  final String? code;
  final int? statusCode;

  /// The session is gone (logged in on another phone, or expired).
  bool get unauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// One row as sent to / received from the cloud.
class SyncRow {
  const SyncRow({
    required this.table,
    required this.id,
    required this.at,
    this.data,
    this.deleted = false,
    this.seq,
  });

  factory SyncRow.fromJson(Map<String, dynamic> json) => SyncRow(
        table: json['table'] as String,
        id: json['id'] as String,
        at: (json['at'] as num).toInt(),
        data: json['data'] as Map<String, dynamic>?,
        deleted: json['deleted'] == true,
        seq: (json['seq'] as num?)?.toInt(),
      );

  final String table;
  final String id;

  /// Phone time of the change, epoch ms. The newest change wins.
  final int at;
  final Map<String, dynamic>? data;
  final bool deleted;

  /// Cloud order, only on pulled rows.
  final int? seq;

  Map<String, dynamic> toJson() => {
        'table': table,
        'id': id,
        'at': at,
        if (deleted) 'deleted': true else 'data': data,
      };
}

class SyncPage {
  const SyncPage({
    required this.account,
    required this.rows,
    required this.next,
    required this.more,
  });

  final String account;
  final List<SyncRow> rows;
  final int next;
  final bool more;
}

/// HTTP side of cloud sync, on the subscription worker (`/v1/sync/*`).
/// Uses the session token saved at registration or login.
class SyncApi {
  SyncApi(this._secure, [http.Client? client])
      : _client = client ?? http.Client();

  final SecureStore _secure;
  final http.Client _client;

  static const _timeout = Duration(seconds: 30);

  /// Cloud sync needs the server URL in this build and a registered account.
  Future<bool> get ready async =>
      AppConfig.subscriptionConfigured &&
      await _secure.read(SecureStore.subscriptionToken) != null;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('${AppConfig.subscriptionApiUrl}$path')
          .replace(queryParameters: query);

  Future<Map<String, String>> _headers() async {
    final token = await _secure.read(SecureStore.subscriptionToken);
    if (token == null) {
      throw const SyncApiException('Registration is not complete.');
    }
    return {
      'content-type': 'application/json',
      'authorization': 'Bearer $token',
    };
  }

  /// Returns the account id the rows were saved under.
  Future<String> push(List<SyncRow> rows) async {
    final response = await _client
        .post(
          _uri('/v1/sync/push'),
          headers: await _headers(),
          body: jsonEncode({
            'changes': [for (final row in rows) row.toJson()],
          }),
        )
        .timeout(_timeout);
    return _decode(response)['account'] as String;
  }

  Future<SyncPage> pull(int after) async {
    final response = await _client
        .get(_uri('/v1/sync/pull', {'after': '$after'}),
            headers: await _headers())
        .timeout(_timeout);
    final data = _decode(response);
    return SyncPage(
      account: data['account'] as String,
      rows: [
        for (final row in data['rows'] as List<dynamic>)
          SyncRow.fromJson(row as Map<String, dynamic>),
      ],
      next: (data['next'] as num).toInt(),
      more: data['more'] == true,
    );
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw SyncApiException('Cloud sync failed (${response.statusCode}).',
          statusCode: response.statusCode);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = data['error'] as Map<String, dynamic>?;
      throw SyncApiException(
        error?['message'] as String? ?? 'Cloud sync failed.',
        code: error?['code'] as String?,
        statusCode: response.statusCode,
      );
    }
    return data;
  }
}
