// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import 'package:aud_midi_web/aud_midi_web.dart';
import 'package:test/test.dart';

void main() {
  group('WebMidiMessage', () {
    test('holds the data and the receive time of one message', () {
      final WebMidiMessage message = (
        data: Uint8List.fromList([0xC0, 0x05]),
        timeStamp: 1500.25,
      );

      expect(message.data, equals([0xC0, 0x05]));
      expect(message.timeStamp, 1500.25);
    });
  });
}
