// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_web/aud_midi_web.dart';
import 'package:test/test.dart';

void main() {
  const api = WebMidiUnavailableApi();

  group('WebMidiUnavailableApi', () {
    group('requestAccess(sysEx, software)', () {
      for (final sysEx in [false, true]) {
        test('rejects like a browser without MIDI, sysEx: $sysEx', () {
          expect(
            api.requestAccess(sysEx: sysEx, software: false),
            throwsA(
              isA<WebMidiDomException>()
                  .having((e) => e.name, 'name', 'NotSupportedError')
                  .having(
                    (e) => e.message,
                    'message',
                    'Web MIDI is not available on this platform',
                  ),
            ),
          );
        });
      }
    });

    group('now()', () {
      test('runs monotonically from a small value', () async {
        final first = api.now();
        await Future<void>.delayed(const Duration(milliseconds: 2));
        final second = api.now();

        expect(first, greaterThanOrEqualTo(0));
        expect(second, greaterThan(first));
      });
    });

    group('isAvailable', () {
      test('is false', () {
        expect(api.isAvailable, isFalse);
      });
    });

    group('isSecureContext', () {
      test('is true, as no page restricts Web MIDI', () {
        expect(api.isSecureContext, isTrue);
      });
    });
  });
}
