// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import 'package:aud_midi_web/aud_midi_web.dart';
import 'package:test/test.dart';

void main() {
  group('WebMidiInputHandle', () {
    test('is a port that delivers messages', () async {
      final WebMidiInputHandle input = _Input();

      final message = await input.messages.single;

      expect(input, isA<WebMidiPortHandle>());
      expect(message.data, equals([0x90, 0x3C, 0x64]));
      expect(message.timeStamp, 12.5);
    });
  });
}

// #############################################################################
/// An input that delivers one Note On.
final class _Input implements WebMidiInputHandle {
  @override
  Stream<WebMidiMessage> get messages => Stream.value((
    data: Uint8List.fromList([0x90, 0x3C, 0x64]),
    timeStamp: 12.5,
  ));

  @override
  Future<void> open() async {}

  @override
  Future<void> close() async {}

  @override
  String get id => 'in';

  @override
  String? get name => null;

  @override
  String? get manufacturer => null;

  @override
  String? get version => null;

  @override
  String get state => 'connected';

  @override
  String get connection => 'open';
}
