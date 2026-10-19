// Copyright 2024 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

part of 'rest_library.dart';

/// RestTransport makes requests out to the REST endpoints of the configured backend.
class RestTransport implements DataConnectTransport {
  /// Initializes necessary protocol and port.
  RestTransport(
    this.transportOptions,
    this.options,
    this.appId,
    this.sdkType,
    this.appCheck,
  ) {
    String protocol = 'http';
    if (transportOptions.isSecure ?? true) {
      protocol += 's';
    }
    String host = transportOptions.host;
    int port = transportOptions.port ?? 443;
    String project = options.projectId;
    String location = options.location;
    String service = options.serviceId;
    String connector = options.connector;
    url =
        '$protocol://$host:$port/v1/projects/$project/locations/$location/services/$service/connectors/$connector';
  }

  @override
  FirebaseAppCheck? appCheck;

  @override
  CallerSDKType sdkType;

  /// Current endpoint URL.
  @visibleForTesting
  late String url;

  @visibleForTesting
  // ignore: use_setters_to_change_properties
  void setHttp(http.Client client) {
    _client = client;
  }

  http.Client _client = http.Client();

  /// Current host configuration.
  @override
  TransportOptions transportOptions;

  /// Data Connect backend configuration options.
  @override
  DataConnectOptions options;

  /// Firebase application ID.
  @override
  String appId;

  /// Invokes the current operation, whether its a query or mutation.
  Future<ServerResponse> invokeOperation<Data, Variables>(
    String queryName,
    String endpoint,
    Deserializer<Data> deserializer,
    Serializer<Variables>? serializer,
    Variables? vars,
    String? authToken,
  ) async {
    String project = options.projectId;
    String location = options.location;
    String service = options.serviceId;
    String connector = options.connector;
    Map<String, String> headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'x-goog-api-client': getGoogApiVal(sdkType, packageVersion),
      'x-firebase-client': getFirebaseClientVal(packageVersion),
      'x-client-version': 'flutter/$packageVersion',
    };
    String? appCheckToken;
    try {
      appCheckToken = await appCheck?.getToken();
    } catch (e) {
      log('Unable to get app check token: $e');
    }
    if (authToken != null) {
      headers['X-Firebase-Auth-Token'] = authToken;
    }
    if (appCheckToken != null) {
      headers['X-Firebase-AppCheck'] = appCheckToken;
    }
    headers['x-firebase-gmpid'] = appId;

    Map<String, dynamic> body = {
      'name':
          'projects/$project/locations/$location/services/$service/connectors/$connector',
      'operationName': queryName,
    };
    if (vars != null && serializer != null) {
      body['variables'] = json.decode(serializer(vars));
    }
    try {
      http.Response r = await _client.post(
        Uri.parse('$url:$endpoint'),
        body: json.encode(body),
        headers: headers,
      );
      final String rawBody = utf8.decode(r.bodyBytes, allowMalformed: true);
      Object? decodedBody;
      try {
        decodedBody = jsonDecode(rawBody);
      } on FormatException {
        decodedBody = null;
      }

      if (r.statusCode != 200) {
        String message = rawBody;
        if (decodedBody is Map && decodedBody['message'] != null) {
          final Object? rawMessage = decodedBody['message'];
          message = rawMessage is String ? rawMessage : rawMessage.toString();
        }
        throw DataConnectError(
          r.statusCode == 401
              ? DataConnectErrorCode.unauthorized
              : DataConnectErrorCode.other,
          "Received a status code of ${r.statusCode} with a message '$message'",
        );
      }

      if (decodedBody is! Map<String, dynamic>) {
        throw DataConnectError(
          DataConnectErrorCode.other,
          'Invalid JSON object in response body',
        );
      }
      final Map<String, dynamic> bodyJson = decodedBody;
      final Object? rawExtensions = bodyJson['extensions'];
      final Map<String, dynamic>? extensions = rawExtensions is Map
          ? Map<String, dynamic>.from(rawExtensions)
          : null;
      final serverResponse = ServerResponse(bodyJson, extensions: extensions);
      if (extensions != null && extensions.containsKey('ttl')) {
        final Duration? parsedTtl = _parseTtl(extensions['ttl']);
        if (parsedTtl != null) {
          serverResponse.ttl = parsedTtl;
        }
      }
      return serverResponse;
    } catch (e) {
      if (e is DataConnectError) {
        rethrow;
      }
      throw DataConnectError(
        DataConnectErrorCode.other,
        'Failed to invoke operation: $e',
      );
    }
  }

  static const int _kMaxTtlSeconds = 315360000;

  static Duration? _parseTtl(Object? rawTtl) {
    num? seconds;
    if (rawTtl is num) {
      seconds = rawTtl;
    } else if (rawTtl is String) {
      final String trimmed = rawTtl.trim();
      final String numericPart = trimmed.endsWith('s')
          ? trimmed.substring(0, trimmed.length - 1)
          : trimmed;
      seconds = num.tryParse(numericPart);
    }
    if (seconds == null || seconds.isNaN) {
      return null;
    }
    if (seconds.isNegative) {
      return Duration.zero;
    }
    if (seconds > _kMaxTtlSeconds) {
      return const Duration(seconds: _kMaxTtlSeconds);
    }
    return Duration(seconds: seconds.floor());
  }

  /// Invokes query REST endpoint.
  @override
  Future<ServerResponse> invokeQuery<Data, Variables>(
    String operationId,
    String queryName,
    Deserializer<Data> deserializer,
    Serializer<Variables>? serializer,
    Variables? vars,
    String? token,
  ) async {
    return invokeOperation(
      queryName,
      'executeQuery',
      deserializer,
      serializer,
      vars,
      token,
    );
  }

  /// Invokes mutation REST endpoint.
  @override
  Future<ServerResponse> invokeMutation<Data, Variables>(
    String operationId,
    String queryName,
    Deserializer<Data> deserializer,
    Serializer<Variables>? serializer,
    Variables? vars,
    String? token,
  ) async {
    return invokeOperation(
      queryName,
      'executeMutation',
      deserializer,
      serializer,
      vars,
      token,
    );
  }

  /// WebSockets are now handled by WebSocketTransport in FirebaseDataConnect.
  @override
  Stream<ServerResponse> invokeStreamQuery<Data, Variables>(
    String operationId,
    String queryName,
    Deserializer<Data> deserializer,
    Serializer<Variables>? serializer,
    Variables? vars,
    String? token,
  ) {
    throw UnsupportedError(
        'Streaming should be routed through WebSocketTransport');
  }
}

/// Initializes Rest transport for Data Connect.
DataConnectTransport getTransport(
  TransportOptions transportOptions,
  DataConnectOptions options,
  String appId,
  CallerSDKType sdkType,
  FirebaseAppCheck? appCheck,
) =>
    RestTransport(transportOptions, options, appId, sdkType, appCheck);
