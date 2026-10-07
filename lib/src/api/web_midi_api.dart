// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'web_midi_access.dart';
import 'web_midi_dom_exception.dart';

// #############################################################################
/// The entry point of the browser's Web MIDI API as the backend sees it.
///
/// In the browser `WebMidiBrowserApi` implements it with `package:web`;
/// elsewhere [WebMidiUnavailableApi] stands in. Implementations hold no MIDI
/// logic: they pass values and events through and turn JavaScript errors
/// into [WebMidiDomException]s, so the backend runs and is tested on the
/// Dart VM with a fake.
abstract interface class WebMidiApi {
  // ...........................................................................
  /// Requests access to the MIDI ports, like
  /// `navigator.requestMIDIAccess({sysex, software})`.
  ///
  /// - [sysEx] asks for System Exclusive messages, a stronger permission
  /// - [software] asks for software synthesizers, too
  ///
  /// Throws a [WebMidiDomException] when the browser rejects the request.
  Future<WebMidiAccess> requestAccess({
    required bool sysEx,
    required bool software,
  });

  // ...........................................................................
  /// Returns `performance.now()`: the milliseconds since the time origin of
  /// the page, the clock of all Web MIDI timestamps.
  double now();

  // ...........................................................................
  /// Whether the browser offers `navigator.requestMIDIAccess`.
  bool get isAvailable;

  /// Whether the page runs in a secure context (https or localhost), which
  /// Web MIDI requires.
  bool get isSecureContext;
}
