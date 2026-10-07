// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:aud_midi_web/aud_midi_web.dart';
import 'package:test/test.dart';

void main() {
  const withSysEx = WebMidiMessageValidator(sysExEnabled: true);
  const withoutSysEx = WebMidiMessageValidator(sysExEnabled: false);

  ({MidiDiagnosticKind kind, String cause})? check(
    WebMidiMessageValidator validator,
    String hex,
  ) => validator.check(MidiBytes.fromHex(hex).bytes);

  group('WebMidiMessageValidator', () {
    group('check(bytes)', () {
      for (final hex in [
        '',
        '90 3c 64',
        'c0 05',
        '90 3c 64 80 3c 00 d0 7f e0 00 40',
        'f8 fa fb fc fe ff',
        'f1 20 f2 00 10 f3 01 f6',
        '90 f8 3c fe 64',
        'f0 7e 7f 06 01 f7',
        'f0 7e f8 7f f7 b0 07 64',
      ]) {
        test('accepts "$hex"', () {
          expect(check(withSysEx, hex), isNull);
        });
      }

      for (final (hex, cause) in [
        (
          '90 3c 64 3e 64',
          'Data byte 0x3E at index 3 has no status byte; '
              'Web MIDI refuses running status',
        ),
        (
          '3c',
          'Data byte 0x3C at index 0 has no status byte; '
              'Web MIDI refuses running status',
        ),
        ('f4', 'Undefined status byte 0xF4 at index 0'),
        ('f8 f5', 'Undefined status byte 0xF5 at index 1'),
        ('f9', 'Undefined status byte 0xF9 at index 0'),
        ('90 fd 3c 64', 'Undefined status byte 0xFD at index 1'),
        ('f7', 'End of System Exclusive at index 0 has no start'),
        ('f0 7e 7f', 'System Exclusive at index 0 has no end'),
        (
          'f0 7e 90 3c 64',
          'Status byte 0x90 at index 2 interrupts the message that starts '
              'at index 0',
        ),
        ('90 3c', 'Message at index 0 is incomplete'),
        ('f8 c0', 'Message at index 1 is incomplete'),
        (
          '90 3c 80 3c 00',
          'Status byte 0x80 at index 2 interrupts the message that starts '
              'at index 0',
        ),
      ]) {
        test('refuses "$hex" as invalid data', () {
          expect(
            check(withSysEx, hex),
            equals((kind: MidiDiagnosticKind.invalidData, cause: cause)),
          );
        });
      }

      for (final hex in ['f0 7e 7f 06 01 f7', '90 3c 64 f0 7e f7']) {
        test('refuses System Exclusive without permission in "$hex"', () {
          final index = hex.startsWith('f0') ? 0 : 3;

          expect(
            check(withoutSysEx, hex),
            equals((
              kind: MidiDiagnosticKind.untranslatable,
              cause:
                  'System Exclusive at index $index needs a MIDI access '
                  'with sysEx enabled',
            )),
          );
        });
      }

      test('accepts other messages without permission for SysEx', () {
        expect(check(withoutSysEx, '90 3c 64 f8'), isNull);
      });
    });

    group('sysExEnabled', () {
      test('tells whether System Exclusive is permitted', () {
        expect([
          withSysEx.sysExEnabled,
          withoutSysEx.sysExEnabled,
        ], equals([true, false]));
      });
    });
  });
}
