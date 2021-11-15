// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database_platform_interface/firebase_database_platform_interface.dart';
import 'package:firebase_database_platform_interface/src/method_channel/method_channel_database.dart';
import 'package:firebase_database_platform_interface/src/method_channel/method_channel_database_reference.dart';
import 'package:firebase_database_platform_interface/src/method_channel/method_channel_on_disconnect.dart';
import 'package:firebase_database_platform_interface/src/method_channel/method_channel_query.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_common.dart';

void main() {
  initializeMethodChannel();
  late FirebaseApp app;
  late BinaryMessenger messenger;

  setUpAll(() async {
    app = await Firebase.initializeApp(
      name: 'testApp',
      options: const FirebaseOptions(
        appId: '1:1234567890:ios:42424242424242',
        apiKey: '123',
        projectId: '123',
        messagingSenderId: '1234567890',
      ),
    );

    messenger = ServicesBinding.instance!.defaultBinaryMessenger;
  });

  group('$MethodChannelDatabase', () {
    const channel = MethodChannel('plugins.flutter.io/firebase_database');
    const eventChannel = MethodChannel('mock/path');

    final List<MethodCall> log = <MethodCall>[];

    const String databaseURL = 'https://fake-database-url2.firebaseio.com';
    late MethodChannelDatabase database;

    setUp(() async {
      database = MethodChannelDatabase(app: app, databaseURL: databaseURL);

      channel.setMockMethodCallHandler((MethodCall methodCall) async {
        log.add(methodCall);

        switch (methodCall.method) {
          case 'Query#observe':
            return 'mock/path';
          case 'FirebaseDatabase#setPersistenceEnabled':
            return true;
          case 'FirebaseDatabase#setPersistenceCacheSizeBytes':
            return true;
          case 'DatabaseReference#runTransaction':
            late Map<String, dynamic> updatedValue;

            Future<void> simulateTransaction(
              int transactionKey,
              String key,
              dynamic data,
            ) async {
              await messenger.handlePlatformMessage(
                channel.name,
                channel.codec.encodeMethodCall(
                  MethodCall(
                    'DoTransaction',
                    <String, dynamic>{
                      'transactionKey': transactionKey,
                      'snapshot': <String, dynamic>{
                        'key': key,
                        'value': data,
                      },
                    },
                  ),
                ),
                (data) {
                  final decoded = channel.codec.decodeEnvelope(data!);
                  updatedValue = decoded.cast<String, dynamic>();
                },
              );
            }

            await simulateTransaction(0, 'fakeKey', {'fakeKey': 'fakeValue'});

            return <String, dynamic>{
              'error': null,
              'committed': true,
              'snapshot': <String, dynamic>{
                'key': 'fakeKey',
                'value': updatedValue
              },
              'childKeys': ['fakeKey']
            };
          default:
            return null;
        }
      });

      log.clear();
    });

    test('setPersistenceEnabled', () async {
      await database.setPersistenceEnabled(false);
      await database.setPersistenceEnabled(true);
      expect(
        log,
        <Matcher>[
          isMethodCall(
            'FirebaseDatabase#setPersistenceEnabled',
            arguments: <String, dynamic>{
              'appName': app.name,
              'databaseURL': databaseURL,
              'enabled': false,
            },
          ),
          isMethodCall(
            'FirebaseDatabase#setPersistenceEnabled',
            arguments: <String, dynamic>{
              'appName': app.name,
              'databaseURL': databaseURL,
              'enabled': true,
            },
          ),
        ],
      );
    });

    test('setPersistentCacheSizeBytes', () async {
      await database.setPersistenceCacheSizeBytes(42);
      expect(
        log,
        <Matcher>[
          isMethodCall(
            'FirebaseDatabase#setPersistenceCacheSizeBytes',
            arguments: <String, dynamic>{
              'appName': app.name,
              'databaseURL': databaseURL,
              'cacheSize': 42,
            },
          ),
        ],
      );
    });

    test('goOnline', () async {
      await database.goOnline();
      expect(
        log,
        <Matcher>[
          isMethodCall(
            'FirebaseDatabase#goOnline',
            arguments: <String, dynamic>{
              'appName': app.name,
              'databaseURL': databaseURL,
            },
          ),
        ],
      );
    });

    test('goOffline', () async {
      await database.goOffline();
      expect(
        log,
        <Matcher>[
          isMethodCall(
            'FirebaseDatabase#goOffline',
            arguments: <String, dynamic>{
              'appName': app.name,
              'databaseURL': databaseURL,
            },
          ),
        ],
      );
    });

    test('purgeOutstandingWrites', () async {
      await database.purgeOutstandingWrites();
      expect(
        log,
        <Matcher>[
          isMethodCall(
            'FirebaseDatabase#purgeOutstandingWrites',
            arguments: <String, dynamic>{
              'appName': app.name,
              'databaseURL': databaseURL,
            },
          ),
        ],
      );
    });

    group('$MethodChannelDatabaseReference', () {
      test('set', () async {
        final dynamic value = <String, dynamic>{'hello': 'world'};
        final dynamic serverValue = <String, dynamic>{
          'qux': ServerValue.increment(8)
        };
        const int priority = 42;
        await database.ref('foo').set(value);
        await database.ref('bar').setWithPriority(value, priority);
        await database.ref('baz').set(serverValue);
        expect(
          log,
          <Matcher>[
            isMethodCall(
              'DatabaseReference#set',
              arguments: <String, dynamic>{
                'appName': app.name,
                'databaseURL': databaseURL,
                'path': 'foo',
                'value': value,
                'priority': null,
              },
            ),
            isMethodCall(
              'DatabaseReference#set',
              arguments: <String, dynamic>{
                'appName': app.name,
                'databaseURL': databaseURL,
                'path': 'bar',
                'value': value,
                'priority': priority,
              },
            ),
            isMethodCall(
              'DatabaseReference#set',
              arguments: <String, dynamic>{
                'appName': app.name,
                'databaseURL': databaseURL,
                'path': 'baz',
                'value': {
                  'qux': {
                    '.sv': {'increment': 8}
                  }
                },
                'priority': null,
              },
            ),
          ],
        );
      });
      test('update', () async {
        final dynamic value = <String, dynamic>{'hello': 'world'};
        await database.ref('foo').update(value);
        expect(
          log,
          <Matcher>[
            isMethodCall(
              'DatabaseReference#update',
              arguments: <String, dynamic>{
                'appName': app.name,
                'databaseURL': databaseURL,
                'path': 'foo',
                'value': value,
              },
            ),
          ],
        );
      });

      test('setPriority', () async {
        const int priority = 42;
        await database.ref('foo').setPriority(priority);
        expect(
          log,
          <Matcher>[
            isMethodCall(
              'DatabaseReference#setPriority',
              arguments: <String, dynamic>{
                'appName': app.name,
                'databaseURL': databaseURL,
                'path': 'foo',
                'priority': priority,
              },
            ),
          ],
        );
      });

      test('runTransaction', () async {
        final ref = database.ref('foo');

        final result = await ref.runTransaction((value) {
          return {
            ...value,
            'fakeKey': 'updated ${value['fakeKey']}',
          };
        });

        expect(
          log,
          <Matcher>[
            isMethodCall(
              'DatabaseReference#runTransaction',
              arguments: <String, dynamic>{
                'appName': app.name,
                'databaseURL': databaseURL,
                'path': 'foo',
                'transactionKey': 0,
                'transactionTimeout': 5000,
              },
            ),
          ],
        );

        expect(result.committed, equals(true));

        expect(
          result.snapshot.value,
          equals(<String, dynamic>{'fakeKey': 'updated fakeValue'}),
        );
      });
    });

    group('$MethodChannelOnDisconnect', () {
      test('set', () async {
        final dynamic value = <String, dynamic>{'hello': 'world'};
        const int priority = 42;
        final DatabaseReferencePlatform ref = database.ref();
        await ref.child('foo').onDisconnect().set(value);
        await ref.child('bar').onDisconnect().setWithPriority(value, priority);
        await ref
            .child('psi')
            .onDisconnect()
            .setWithPriority(value, 'priority');
        await ref.child('por').onDisconnect().setWithPriority(value, value);
        expect(
          log,
          <Matcher>[
            isMethodCall(
              'OnDisconnect#set',
              arguments: <String, dynamic>{
                'appName': app.name,
                'databaseURL': databaseURL,
                'path': 'foo',
                'value': value,
                'priority': null,
              },
            ),
            isMethodCall(
              'OnDisconnect#set',
              arguments: <String, dynamic>{
                'appName': app.name,
                'databaseURL': databaseURL,
                'path': 'bar',
                'value': value,
                'priority': priority,
              },
            ),
            isMethodCall(
              'OnDisconnect#set',
              arguments: <String, dynamic>{
                'appName': app.name,
                'databaseURL': databaseURL,
                'path': 'psi',
                'value': value,
                'priority': 'priority',
              },
            ),
            isMethodCall(
              'OnDisconnect#set',
              arguments: <String, dynamic>{
                'appName': app.name,
                'databaseURL': databaseURL,
                'path': 'por',
                'value': value,
                'priority': value,
              },
            ),
          ],
        );
      });
      test('update', () async {
        final dynamic value = <String, dynamic>{'hello': 'world'};
        await database.ref('foo').onDisconnect().update(value);
        expect(
          log,
          <Matcher>[
            isMethodCall(
              'OnDisconnect#update',
              arguments: <String, dynamic>{
                'appName': app.name,
                'databaseURL': databaseURL,
                'path': 'foo',
                'value': value,
              },
            ),
          ],
        );
      });
      test('cancel', () async {
        await database.ref('foo').onDisconnect().cancel();
        expect(
          log,
          <Matcher>[
            isMethodCall(
              'OnDisconnect#cancel',
              arguments: <String, dynamic>{
                'appName': app.name,
                'databaseURL': databaseURL,
                'path': 'foo',
              },
            ),
          ],
        );
      });
      test('remove', () async {
        await database.ref('foo').onDisconnect().remove();
        expect(
          log,
          <Matcher>[
            isMethodCall(
              'OnDisconnect#set',
              arguments: <String, dynamic>{
                'appName': app.name,
                'databaseURL': databaseURL,
                'path': 'foo',
                'value': null,
                'priority': null,
              },
            ),
          ],
        );
      });
    });

    group('$MethodChannelQuery', () {
      test('keepSynced, simple query', () async {
        const String path = 'foo';
        final QueryPlatform query = database.ref(path);
        await query.keepSynced(true);
        expect(
          log,
          <Matcher>[
            isMethodCall(
              'Query#keepSynced',
              arguments: <String, dynamic>{
                'appName': app.name,
                'databaseURL': databaseURL,
                'path': path,
                'parameters': <String, dynamic>{},
                'value': true,
              },
            ),
          ],
        );
      });
      test('keepSynced, complex query', () async {
        const int startAt = 42;
        const String path = 'foo';
        const String childKey = 'bar';
        const bool endAt = true;
        const String endAtKey = 'baz';
        final QueryPlatform query = database
            .ref()
            .child(path)
            .orderByChild(childKey)
            .startAt(startAt)
            .endAt(endAt, key: endAtKey);
        await query.keepSynced(false);
        final Map<String, dynamic> expectedParameters = <String, dynamic>{
          'orderBy': 'child',
          'orderByChildKey': childKey,
          'startAt': startAt,
          'endAt': endAt,
          'endAtKey': endAtKey,
        };
        expect(
          log,
          <Matcher>[
            isMethodCall(
              'Query#keepSynced',
              arguments: <String, dynamic>{
                'appName': app.name,
                'databaseURL': databaseURL,
                'path': path,
                'parameters': expectedParameters,
                'value': false
              },
            ),
          ],
        );
      });
      test('observing error events', () async {
        const String errorCode = 'some-error';

        final QueryPlatform query = database.ref('some/path');

        Future<void> simulateError(String errorMessage) async {
          await eventChannel.binaryMessenger.handlePlatformMessage(
            eventChannel.name,
            eventChannel.codec.encodeErrorEnvelope(
              code: errorCode,
              message: errorMessage,
            ),
            (_) {},
          );
        }

        final errors = AsyncQueue<FirebaseException>();

        final subscription = query.onValue.listen((_) {}, onError: errors.add);
        await Future<void>.delayed(Duration.zero);

        await simulateError('Bad foo');
        await simulateError('Bad bar');

        final FirebaseException error1 = await errors.remove();
        final FirebaseException error2 = await errors.remove();

        await subscription.cancel();

        expect(
          error1.toString(),
          '[firebase_database/some-error] Bad foo',
        );

        expect(error1.code, errorCode);
        expect(error1.message, 'Bad foo');

        expect(error2.code, errorCode);
        expect(error2.message, 'Bad bar');
      });

      test('observing value events', () async {
        const String path = 'foo';
        final QueryPlatform query = database.ref(path);

        Future<void> simulateEvent(Map<Object?, Object?> event) async {
          await eventChannel.binaryMessenger.handlePlatformMessage(
            eventChannel.name,
            eventChannel.codec.encodeSuccessEnvelope(event),
            (_) {},
          );
        }

        Map<Object?, Object?> createValueEvent(dynamic value) {
          return {
            'eventType': 'EventType.value',
            'snapshot': {
              'value': value,
              'key': path.split('/').last,
            },
          };
        }

        final AsyncQueue<DatabaseEventPlatform> events =
            AsyncQueue<DatabaseEventPlatform>();

        // Subscribe and allow subscription to complete.
        final subscription = query.onValue.listen(events.add);
        await Future<void>.delayed(Duration.zero);

        await simulateEvent(createValueEvent(1));
        await simulateEvent(createValueEvent(2));

        final DatabaseEventPlatform event1 = await events.remove();
        final DatabaseEventPlatform event2 = await events.remove();

        expect(event1.snapshot.key, path);
        expect(event1.snapshot.value, 1);
        expect(event2.snapshot.key, path);
        expect(event2.snapshot.value, 2);

        // Cancel subscription and allow cancellation to complete.
        await subscription.cancel();
        await Future.delayed(Duration.zero);

        expect(
          log,
          <Matcher>[
            isMethodCall(
              'Query#observe',
              arguments: <String, dynamic>{
                'appName': app.name,
                'databaseURL': databaseURL,
                'path': path,
                'parameters': <String, dynamic>{},
                'eventType': 'EventType.value',
              },
            )
          ],
        );
      });
    });
  });
}

/// Queue whose remove operation is asynchronous, awaiting a corresponding add.
class AsyncQueue<T> {
  Map<int, Completer<T>> _completers = <int, Completer<T>>{};
  int _nextToRemove = 0;
  int _nextToAdd = 0;

  void add(T element) {
    _completer(_nextToAdd++).complete(element);
  }

  Future<T> remove() {
    return _completer(_nextToRemove++).future;
  }

  Completer<T> _completer(int index) {
    if (_completers.containsKey(index)) {
      return _completers.remove(index)!;
    } else {
      return _completers[index] = Completer<T>();
    }
  }
}