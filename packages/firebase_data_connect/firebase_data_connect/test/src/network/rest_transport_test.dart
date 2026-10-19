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

import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_data_connect/src/common/common_library.dart';
import 'package:firebase_data_connect/src/dataconnect_version.dart';
import 'package:firebase_data_connect/src/network/rest_library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'rest_transport_test.mocks.dart';

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

@GenerateMocks([http.Client, User, FirebaseAppCheck])
void main() {
  late RestTransport transport;
  late MockClient mockHttpClient;
  late MockFirebaseAuth mockAuth;
  late MockFirebaseAppCheck mockAppCheck;
  late MockUser mockUser;

  setUp(() {
    mockHttpClient = MockClient();
    mockAuth = MockFirebaseAuth();
    mockAppCheck = MockFirebaseAppCheck();
    mockUser = MockUser();
    when(mockAuth.currentUser).thenReturn(mockUser);

    transport = RestTransport(
      TransportOptions('testhost', 443, true),
      DataConnectOptions(
        'testProject',
        'testLocation',
        'testConnector',
        'testService',
      ),
      'testAppId',
      CallerSDKType.core,
      mockAppCheck,
    );

    transport.setHttp(mockHttpClient);
  });

  group('RestTransport', () {
    test('should correctly initialize URL with secure protocol', () {
      expect(
        transport.url,
        'https://testhost:443/v1/projects/testProject/locations/testLocation/services/testService/connectors/testConnector',
      );
    });

    test('should correctly initialize URL with insecure protocol', () {
      final insecureTransport = RestTransport(
        TransportOptions('testhost', 443, false),
        DataConnectOptions(
          'testProject',
          'testLocation',
          'testConnector',
          'testService',
        ),
        'testAppId',
        CallerSDKType.core,
        mockAppCheck,
      );

      expect(
        insecureTransport.url,
        'http://testhost:443/v1/projects/testProject/locations/testLocation/services/testService/connectors/testConnector',
      );
    });

    test('invokeOperation should throw unauthorized error on 401 response',
        () async {
      final mockResponse = http.Response('Unauthorized', 401);
      when(
        mockHttpClient.post(
          any,
          headers: anyNamed('headers'),
          body: anyNamed('body'),
        ),
      ).thenAnswer((_) async => mockResponse);

      String deserializer(String data) => 'Deserialized Data';

      expect(
        () => transport.invokeOperation(
          'testQuery',
          'executeQuery',
          deserializer,
          null,
          null,
          null,
        ),
        throwsA(isA<DataConnectError>()),
      );
    });

    test('invokeOperation should throw other errors on non-200 responses',
        () async {
      final mockResponse = http.Response('{"message": "Some error"}', 500);
      when(
        mockHttpClient.post(
          any,
          headers: anyNamed('headers'),
          body: anyNamed('body'),
        ),
      ).thenAnswer((_) async => mockResponse);

      String deserializer(String data) => 'Deserialized Data';

      expect(
        () => transport.invokeOperation(
          'testQuery',
          'executeQuery',
          deserializer,
          null,
          null,
          null,
        ),
        throwsA(isA<DataConnectError>()),
      );
    });

    test('invokeQuery should call invokeOperation with correct endpoint',
        () async {
      final mockResponse = http.Response('{"data": {"key": "value"}}', 200);
      when(
        mockHttpClient.post(
          any,
          headers: anyNamed('headers'),
          body: anyNamed('body'),
        ),
      ).thenAnswer((_) async => mockResponse);

      String deserializer(String data) => 'Deserialized Data';

      await transport.invokeQuery(
          'testQueryId', 'testQuery', deserializer, null, null, null);

      verify(
        mockHttpClient.post(
          any,
          headers: anyNamed('headers'),
          body: json.encode({
            'name':
                'projects/testProject/locations/testLocation/services/testService/connectors/testConnector',
            'operationName': 'testQuery',
          }),
        ),
      ).called(1);
    });

    test('invokeMutation should call invokeOperation with correct endpoint',
        () async {
      final mockResponse = http.Response('{"data": {"key": "value"}}', 200);
      when(
        mockHttpClient.post(
          any,
          headers: anyNamed('headers'),
          body: anyNamed('body'),
        ),
      ).thenAnswer((_) async => mockResponse);

      String deserializer(String data) => 'Deserialized Mutation Data';

      await transport.invokeMutation(
        'testMutationId',
        'testMutation',
        deserializer,
        null,
        null,
        null,
      );

      verify(
        mockHttpClient.post(
          any,
          headers: anyNamed('headers'),
          body: json.encode({
            'name':
                'projects/testProject/locations/testLocation/services/testService/connectors/testConnector',
            'operationName': 'testMutation',
          }),
        ),
      ).called(1);
    });

    test('invokeOperation should include auth and appCheck tokens in headers',
        () async {
      final mockResponse = http.Response('{"data": {"key": "value"}}', 200);
      when(
        mockHttpClient.post(
          any,
          headers: anyNamed('headers'),
          body: anyNamed('body'),
        ),
      ).thenAnswer((_) async => mockResponse);

      when(mockUser.getIdToken()).thenAnswer((_) async => 'authToken123');
      when(mockAppCheck.getToken()).thenAnswer((_) async => 'appCheckToken123');

      String deserializer(String data) => 'Deserialized Data';

      await transport.invokeOperation(
        'testQuery',
        'executeQuery',
        deserializer,
        null,
        null,
        'authToken123',
      );

      verify(
        mockHttpClient.post(
          any,
          headers: argThat(
            containsPair('X-Firebase-Auth-Token', 'authToken123'),
            named: 'headers',
          ),
          body: anyNamed('body'),
        ),
      ).called(1);
    });
    test('invokeOperation should include x-firebase-client headers', () async {
      final mockResponse = http.Response('{"data": {"key": "value"}}', 200);
      when(
        mockHttpClient.post(
          any,
          headers: anyNamed('headers'),
          body: anyNamed('body'),
        ),
      ).thenAnswer((_) async => mockResponse);

      when(mockUser.getIdToken()).thenAnswer((_) async => 'authToken123');
      when(mockAppCheck.getToken()).thenAnswer((_) async => 'appCheckToken123');

      String deserializer(String data) => 'Deserialized Data';

      await transport.invokeOperation(
        'testQuery',
        'executeQuery',
        deserializer,
        null,
        null,
        'authToken123',
      );

      verify(
        mockHttpClient.post(
          any,
          headers: argThat(
            containsPair(
                'x-firebase-client', getFirebaseClientVal(packageVersion)),
            named: 'headers',
          ),
          body: anyNamed('body'),
        ),
      ).called(1);
    });

    test('invokeOperation should include x-client-version headers', () async {
      final mockResponse = http.Response('{"data": {"key": "value"}}', 200);
      when(
        mockHttpClient.post(
          any,
          headers: anyNamed('headers'),
          body: anyNamed('body'),
        ),
      ).thenAnswer((_) async => mockResponse);

      String deserializer(String data) => 'Deserialized Data';

      await transport.invokeOperation(
        'testQuery',
        'executeQuery',
        deserializer,
        null,
        null,
        'authToken123',
      );

      verify(
        mockHttpClient.post(
          any,
          headers: argThat(
            allOf(
              containsPair('x-client-version', 'flutter/$packageVersion'),
            ),
            named: 'headers',
          ),
          body: anyNamed('body'),
        ),
      ).called(1);
    });

    test(
        'regression #17290 - invokeOperation should correctly decode UTF-8 response with international characters',
        () async {
      // Simulate a server response with Korean characters, where the
      // Content-Type header does NOT include charset=utf-8 (which is
      // what the Firebase emulator sends). Without explicit UTF-8
      // decoding, the http package defaults to latin1, corrupting
      // multi-byte characters.
      const koreanJson =
          '{"data": {"name": "\ud55c\uad6d\uc5b4 \ud14c\uc2a4\ud2b8"}}';
      final mockResponse = http.Response.bytes(
        utf8.encode(koreanJson),
        200,
        headers: {'content-type': 'application/json'},
      );
      when(
        mockHttpClient.post(
          any,
          headers: anyNamed('headers'),
          body: anyNamed('body'),
        ),
      ).thenAnswer((_) async => mockResponse);

      String deserializer(String data) => 'Deserialized Data';

      final result = await transport.invokeOperation(
        'testQuery',
        'executeQuery',
        deserializer,
        null,
        null,
        null,
      );

      expect(result.data['data']['name'],
          equals('\ud55c\uad6d\uc5b4 \ud14c\uc2a4\ud2b8'));
    });

    test(
        'invokeOperation should handle missing auth and appCheck tokens gracefully',
        () async {
      final mockResponse = http.Response('{"data": {"key": "value"}}', 200);
      when(
        mockHttpClient.post(
          any,
          headers: anyNamed('headers'),
          body: anyNamed('body'),
        ),
      ).thenAnswer((_) async => mockResponse);

      when(mockUser.getIdToken()).thenThrow(Exception('Auth error'));
      when(mockAppCheck.getToken()).thenThrow(Exception('AppCheck error'));

      String deserializer(String data) => 'Deserialized Data';

      await transport.invokeOperation(
        'testQuery',
        'executeQuery',
        deserializer,
        null,
        null,
        null,
      );

      verify(
        mockHttpClient.post(
          any,
          headers: argThat(
            isNot(contains('X-Firebase-Auth-Token')),
            named: 'headers',
          ),
          body: anyNamed('body'),
        ),
      ).called(1);
    });

    test(
        'invokeOperation wraps HTML, JSON-array, and non-string-message non-200 responses in DataConnectError with status code (DC-9)',
        () async {
      String deserializer(String data) => 'Deserialized Data';

      // 1. HTML 502 error body preserves status code 502 in DataConnectError.
      when(
        mockHttpClient.post(
          any,
          headers: anyNamed('headers'),
          body: anyNamed('body'),
        ),
      ).thenAnswer(
        (_) async => http.Response('<html>502 Bad Gateway</html>', 502),
      );

      await expectLater(
        () => transport.invokeOperation(
          'testQuery',
          'executeQuery',
          deserializer,
          null,
          null,
          null,
        ),
        throwsA(
          isA<DataConnectError>().having(
            (e) => e.message,
            'message',
            contains('502'),
          ),
        ),
      );

      // 2. JSON array error body does not leak TypeError.
      when(
        mockHttpClient.post(
          any,
          headers: anyNamed('headers'),
          body: anyNamed('body'),
        ),
      ).thenAnswer(
        (_) async => http.Response('[{"error": "bad"}]', 503),
      );

      await expectLater(
        () => transport.invokeOperation(
          'testQuery',
          'executeQuery',
          deserializer,
          null,
          null,
          null,
        ),
        throwsA(
          isA<DataConnectError>().having(
            (e) => e.message,
            'message',
            contains('503'),
          ),
        ),
      );

      // 3. Non-string message field in error body does not leak TypeError.
      when(
        mockHttpClient.post(
          any,
          headers: anyNamed('headers'),
          body: anyNamed('body'),
        ),
      ).thenAnswer(
        (_) async => http.Response('{"message": 12345}', 500),
      );

      await expectLater(
        () => transport.invokeOperation(
          'testQuery',
          'executeQuery',
          deserializer,
          null,
          null,
          null,
        ),
        throwsA(
          isA<DataConnectError>().having(
            (e) => e.message,
            'message',
            allOf(contains('500'), contains('12345')),
          ),
        ),
      );
    });

    test(
        'invokeOperation parses string/float extensions.ttl and clamps negative or overflowing ttl values (DC-1, DC-6)',
        () async {
      String deserializer(String data) => 'Deserialized Data';

      // 1. Proto-JSON string ttl ("30s").
      when(
        mockHttpClient.post(
          any,
          headers: anyNamed('headers'),
          body: anyNamed('body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          '{"data": {"key": "value"}, "extensions": {"ttl": "30s"}}',
          200,
        ),
      );

      final resStringTtl = await transport.invokeOperation(
        'testQuery',
        'executeQuery',
        deserializer,
        null,
        null,
        null,
      );
      expect(resStringTtl.ttl, const Duration(seconds: 30));

      // 2. Huge ttl does not overflow Duration into negative microseconds.
      when(
        mockHttpClient.post(
          any,
          headers: anyNamed('headers'),
          body: anyNamed('body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          '{"data": {"key": "value"}, "extensions": {"ttl": 10000000000000}}',
          200,
        ),
      );

      final resHugeTtl = await transport.invokeOperation(
        'testQuery',
        'executeQuery',
        deserializer,
        null,
        null,
        null,
      );
      expect(resHugeTtl.ttl, isNotNull);
      expect(resHugeTtl.ttl!.isNegative, isFalse);

      // 3. Negative ttl clamps to Duration.zero.
      when(
        mockHttpClient.post(
          any,
          headers: anyNamed('headers'),
          body: anyNamed('body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          '{"data": {"key": "value"}, "extensions": {"ttl": -10}}',
          200,
        ),
      );

      final resNegativeTtl = await transport.invokeOperation(
        'testQuery',
        'executeQuery',
        deserializer,
        null,
        null,
        null,
      );
      expect(resNegativeTtl.ttl, Duration.zero);
    });
  });
}
