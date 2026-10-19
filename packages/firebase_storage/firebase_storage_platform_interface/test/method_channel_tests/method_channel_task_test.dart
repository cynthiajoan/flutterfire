// ignore_for_file: require_trailing_commas
// Copyright 2026, the Chromium project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage_platform_interface/firebase_storage_platform_interface.dart';
import 'package:firebase_storage_platform_interface/src/method_channel/method_channel_firebase_storage.dart';
import 'package:firebase_storage_platform_interface/src/method_channel/method_channel_task.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../mock.dart';

class _TestTask extends MethodChannelTask {
  _TestTask(
    int handle,
    FirebaseStoragePlatform storage,
    String path,
    Future<String> initialTask,
  ) : super(handle, storage, path, initialTask);
}

void main() {
  setupFirebaseStorageMocks();

  late FirebaseStoragePlatform storage;
  const codec = StandardMethodCodec();

  setUpAll(() async {
    final app = await Firebase.initializeApp();
    storage = MethodChannelFirebaseStorage(app: app, bucket: 'bucket-test');
  });

  Future<void> emitTaskEvent(String observerId, Map<String, Object?> event) {
    final channelName =
        '${MethodChannelFirebaseStorage.storageMethodChannelName}/'
        '${MethodChannelFirebaseStorage.storageTaskEventName}/$observerId';
    return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channelName,
      codec.encodeSuccessEnvelope(event),
      (_) {},
    );
  }

  Future<void> emitTaskErrorEnvelope(
    String observerId, {
    required String code,
    required String message,
  }) {
    final channelName =
        '${MethodChannelFirebaseStorage.storageMethodChannelName}/'
        '${MethodChannelFirebaseStorage.storageTaskEventName}/$observerId';
    return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channelName,
      codec.encodeErrorEnvelope(code: code, message: message),
      (_) {},
    );
  }

  void registerTaskEventChannel(String observerId) {
    final channel = MethodChannel(
      '${MethodChannelFirebaseStorage.storageMethodChannelName}/'
      '${MethodChannelFirebaseStorage.storageTaskEventName}/$observerId',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
  }

  group('$MethodChannelTask', () {
    test(
        'preserves readable snapshot.metadata after progress followed by error (ST-1)',
        () async {
      const observerId = 'obs-st-1';
      registerTaskEventChannel(observerId);

      final task = _TestTask(
        1,
        storage,
        '/uploads/file.txt',
        Future<String>.value(observerId),
      );

      final errors = <Object>[];
      final sub = task.snapshotEvents.listen((_) {}, onError: errors.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(Duration.zero);

      await emitTaskEvent(observerId, <String, Object?>{
        'taskState': TaskState.running.index,
        'snapshot': <String, Object?>{
          'path': '/uploads/file.txt',
          'bytesTransferred': 64,
          'totalBytes': 128,
          'metadata': <String, Object?>{
            'bucket': 'bucket-test',
            'fullPath': '/uploads/file.txt',
            'name': 'file.txt',
          },
        },
      });
      await Future<void>.delayed(Duration.zero);

      expect(task.snapshot.metadata?.fullPath, '/uploads/file.txt');

      await emitTaskEvent(observerId, <String, Object?>{
        'taskState': TaskState.error.index,
        'error': <String, Object?>{
          'code': 'Retry-limit-exceeded',
          'message': 'Max retry time for operation exceeded.',
        },
      });
      await Future<void>.delayed(Duration.zero);

      expect(errors, hasLength(1));
      expect(errors.single, isA<FirebaseException>());
      expect(task.snapshot.state, TaskState.error);
      expect(task.snapshot.bytesTransferred, 64);
      expect(task.snapshot.totalBytes, 128);
      expect(task.snapshot.metadata?.fullPath, '/uploads/file.txt');
      expect(task.snapshot.metadata?.bucket, 'bucket-test');
    });

    test(
        'completes onComplete with error when stream throws a PlatformException (ST-3)',
        () async {
      const observerId = 'obs-st-3';
      registerTaskEventChannel(observerId);

      final task = _TestTask(
        2,
        storage,
        '/uploads/fail.txt',
        Future<String>.value(observerId),
      );

      final completionFuture = task.onComplete;
      await Future<void>.delayed(Duration.zero);

      await emitTaskErrorEnvelope(
        observerId,
        code: 'unauthorized',
        message: 'User is not authorized to perform the desired action.',
      );

      await expectLater(
        completionFuture.timeout(const Duration(milliseconds: 200)),
        throwsA(
          isA<FirebaseException>()
              .having((e) => e.code, 'code', 'unauthorized'),
        ),
      );
    });
  });
}
