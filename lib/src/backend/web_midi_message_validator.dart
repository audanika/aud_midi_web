// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import 'package:aud_midi_standard/aud_midi_standard.dart';

// #############################################################################
/// Checks bytes the way `MIDIOutput.send()` does, before the backend hands
/// them to the browser.
///
/// The browser throws on running status, undefined status bytes, incomplete
/// messages and on System Exclusive that is split, unterminated or not
/// permitted (Web MIDI API, `MIDIOutput.send`). Real-time messages may
/// appear anywhere, also between the bytes of another message.
final class WebMidiMessageValidator {
  /// Creates a validator for an access that permits System Exclusive
  /// messages when [sysExEnabled] is true.
  const WebMidiMessageValidator({required this.sysExEnabled});

  // ...........................................................................
  /// Returns why the browser would refuse [bytes], or null when it accepts
  /// them.
  ///
  /// The kind is [MidiDiagnosticKind.untranslatable] for System Exclusive
  /// without permission and [MidiDiagnosticKind.invalidData] otherwise.
  ({MidiDiagnosticKind kind, String cause})? check(Uint8List bytes) {
    var index = 0;
    while (index < bytes.length) {
      final problem = _startProblem(bytes[index], index);
      if (problem != null) return problem;
      final end = _endOf(bytes, index);
      if (end.cause case final cause?) return _invalid(cause);
      index = end.index;
    }
    return null;
  }

  // ...........................................................................
  /// Whether the access permits System Exclusive messages.
  final bool sysExEnabled;

  // ...........................................................................
  /// Returns why [status] at [index] cannot start a message, or null.
  ({MidiDiagnosticKind kind, String cause})? _startProblem(
    int status,
    int index,
  ) {
    if (MidiStatus.isData(status)) {
      return _invalid(
        'Data byte ${_hex(status)} at index $index has no status byte; '
        'Web MIDI refuses running status',
      );
    }
    if (_isUndefined(status)) return _invalid(_undefined(status, index));
    if (status == MidiStatus.endOfSysEx) {
      return _invalid('End of System Exclusive at index $index has no start');
    }
    if (status == MidiStatus.sysEx && !sysExEnabled) {
      return (
        kind: MidiDiagnosticKind.untranslatable,
        cause:
            'System Exclusive at index $index needs a MIDI access with '
            'sysEx enabled',
      );
    }
    return null;
  }

  /// Returns the index after the message that starts at [start], or the
  /// cause why the message does not end properly.
  ({int index, String? cause}) _endOf(Uint8List bytes, int start) {
    final length = MidiStatus.dataLength(bytes[start]);
    final isSysEx = length == MidiStatus.variableLength;
    var dataBytes = 0;
    for (var index = start + 1; index < bytes.length; index++) {
      if (!isSysEx && dataBytes == length) return (index: index, cause: null);
      final byte = bytes[index];
      if (_isUndefined(byte)) {
        return (index: index, cause: _undefined(byte, index));
      }
      if (isSysEx && byte == MidiStatus.endOfSysEx) {
        return (index: index + 1, cause: null);
      }
      if (MidiStatus.isRealTime(byte)) continue;
      if (MidiStatus.isStatus(byte)) {
        return (index: index, cause: _interrupted(byte, index, start));
      }
      dataBytes++;
    }
    if (!isSysEx && dataBytes == length) {
      return (index: bytes.length, cause: null);
    }
    return (
      index: bytes.length,
      cause: isSysEx
          ? 'System Exclusive at index $start has no end'
          : 'Message at index $start is incomplete',
    );
  }

  /// Returns the problem of the kind invalid data with [cause].
  static ({MidiDiagnosticKind kind, String cause}) _invalid(String cause) =>
      (kind: MidiDiagnosticKind.invalidData, cause: cause);

  /// Whether [byte] is one of the undefined status bytes 0xF4, 0xF5, 0xF9
  /// and 0xFD.
  static bool _isUndefined(int byte) =>
      byte == MidiStatus.undefinedF4 ||
      byte == MidiStatus.undefinedF5 ||
      byte == MidiStatus.undefinedF9 ||
      byte == MidiStatus.undefinedFD;

  /// Returns the cause for the undefined status [byte] at [index].
  static String _undefined(int byte, int index) =>
      'Undefined status byte ${_hex(byte)} at index $index';

  /// Returns the cause for the status [byte] at [index] that interrupts
  /// the message starting at [start].
  static String _interrupted(int byte, int index, int start) =>
      'Status byte ${_hex(byte)} at index $index interrupts the message '
      'that starts at index $start';

  /// Returns [byte] as `0x` and two upper-case hex digits.
  static String _hex(int byte) =>
      '0x${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}';
}
