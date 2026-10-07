// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import 'web_midi_dom_exception.dart';
import 'web_midi_port_handle.dart';

// #############################################################################
/// An output port of the browser, a `MIDIOutput`.
abstract interface class WebMidiOutputHandle implements WebMidiPortHandle {
  // ...........................................................................
  /// Sends [data], like `MIDIOutput.send(data, timestamp)`.
  ///
  /// - [data] complete MIDI messages without running status
  /// - [timestamp] when to send, in milliseconds on the clock of
  ///   `performance.now()`; 0 or a time in the past sends at once
  ///
  /// Throws a [WebMidiDomException] when the browser refuses the data.
  void send(Uint8List data, {double timestamp = 0});

  /// Discards the data not sent yet, like `MIDIOutput.clear()`.
  ///
  /// Throws a [WebMidiDomException] when the browser fails, e.g. because it
  /// does not implement `clear()`; see [canClear].
  void clear();

  // ...........................................................................
  /// Whether the browser implements `MIDIOutput.clear()`.
  bool get canClear;
}
