// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_web/aud_midi_web.dart';
import 'package:test/test.dart';

void main() {
  group('WebMidiDomException', () {
    group('WebMidiDomException(name, message, code)', () {
      test('keeps name, message and code', () {
        const exception = WebMidiDomException(
          name: 'InvalidStateError',
          message: 'Port is disconnected',
          code: 11,
        );

        expect([
          exception.name,
          exception.message,
          exception.code,
        ], equals(['InvalidStateError', 'Port is disconnected', 11]));
      });

      test('uses code 0 by default', () {
        const exception = WebMidiDomException(name: 'TypeError', message: '');

        expect(exception.code, 0);
      });
    });

    group('toString()', () {
      test('joins name and message like JavaScript', () {
        const exception = WebMidiDomException(
          name: 'NotAllowedError',
          message: 'Permission denied',
        );

        expect(exception.toString(), 'NotAllowedError: Permission denied');
      });
    });
  });
}
