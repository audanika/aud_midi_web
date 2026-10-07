// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_web/aud_midi_web.dart';
import 'package:test/test.dart';

void main() {
  group('WebMidiAccess', () {
    test('lists inputs and outputs and reports state changes', () async {
      final WebMidiAccess access = _Access();

      final changes = access.stateChanges.toList();

      expect(access.inputs, isEmpty);
      expect(access.outputs, isEmpty);
      expect(access.sysExEnabled, isTrue);
      expect(await changes, hasLength(1));
    });
  });
}

// #############################################################################
/// An access without ports that reports one state change.
final class _Access implements WebMidiAccess {
  @override
  List<WebMidiInputHandle> get inputs => const [];

  @override
  List<WebMidiOutputHandle> get outputs => const [];

  @override
  bool get sysExEnabled => true;

  @override
  Stream<void> get stateChanges => Stream<void>.value(null);
}
