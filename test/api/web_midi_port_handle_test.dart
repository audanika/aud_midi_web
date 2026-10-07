// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_web/aud_midi_web.dart';
import 'package:test/test.dart';

void main() {
  group('WebMidiPortHandle', () {
    test('describes a port and opens and closes it', () async {
      final port = _Port();
      final WebMidiPortHandle handle = port;

      await handle.open();
      final openConnection = handle.connection;
      await handle.close();

      expect([
        handle.id,
        handle.name,
        handle.manufacturer,
        handle.version,
      ], equals(['42', 'Keys', null, null]));
      expect([
        handle.state,
        openConnection,
        handle.connection,
      ], equals(['connected', 'open', 'closed']));
    });
  });
}

// #############################################################################
/// A port that tracks its connection.
final class _Port implements WebMidiPortHandle {
  @override
  Future<void> open() async => connection = 'open';

  @override
  Future<void> close() async => connection = 'closed';

  @override
  String get id => '42';

  @override
  String? get name => 'Keys';

  @override
  String? get manufacturer => null;

  @override
  String? get version => null;

  @override
  String get state => 'connected';

  @override
  String connection = 'closed';
}
