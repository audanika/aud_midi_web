// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'web_midi_message.dart';
import 'web_midi_port_handle.dart';

// #############################################################################
/// An input port of the browser, a `MIDIInput`.
abstract interface class WebMidiInputHandle implements WebMidiPortHandle {
  // ...........................................................................
  /// Delivers the `midimessage` events of the port, one complete MIDI
  /// message each.
  ///
  /// Listening sets `onmidimessage`, which opens the port implicitly;
  /// cancelling the subscription clears it.
  Stream<WebMidiMessage> get messages;
}
