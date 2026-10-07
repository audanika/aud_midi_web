// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import 'package:aud_midi_web/aud_midi_web.dart';
import 'package:test/test.dart';

void main() {
  group('WebMidiOutputHandle', () {
    test('is a port that sends at a time and clears', () {
      final output = _Output();
      final WebMidiOutputHandle handle = output;

      handle.send(Uint8List.fromList([0xF8]));
      handle.send(Uint8List.fromList([0xFA]), timestamp: 20);
      handle.clear();

      expect(handle, isA<WebMidiPortHandle>());
      expect(output.sent, equals(['f8 @ 0.0', 'fa @ 20.0', 'clear']));
      expect(handle.canClear, isTrue);
    });
  });
}

// #############################################################################
/// An output that records what it is asked to do.
final class _Output implements WebMidiOutputHandle {
  final sent = <String>[];

  @override
  void send(Uint8List data, {double timestamp = 0}) => sent.add(
    '${data.map((b) => b.toRadixString(16)).join(' ')} @ $timestamp',
  );

  @override
  void clear() => sent.add('clear');

  @override
  bool get canClear => true;

  @override
  Future<void> open() async {}

  @override
  Future<void> close() async {}

  @override
  String get id => 'out';

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
