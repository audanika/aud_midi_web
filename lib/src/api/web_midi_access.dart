// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'web_midi_input_handle.dart';
import 'web_midi_output_handle.dart';

// #############################################################################
/// The access to the MIDI ports a page was granted, a `MIDIAccess`.
abstract interface class WebMidiAccess {
  // ...........................................................................
  /// The input ports the browser lists right now, `MIDIAccess.inputs`.
  List<WebMidiInputHandle> get inputs;

  /// The output ports the browser lists right now, `MIDIAccess.outputs`.
  List<WebMidiOutputHandle> get outputs;

  /// Whether System Exclusive messages are received and may be sent.
  bool get sysExEnabled;

  /// Reports every `statechange` event: a port appeared, disappeared or was
  /// opened or closed.
  ///
  /// Listening sets `onstatechange`; cancelling the subscription clears it.
  Stream<void> get stateChanges;
}
