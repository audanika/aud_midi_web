// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'web_midi_dom_exception.dart';

// #############################################################################
/// One MIDI port of the browser, a `MIDIPort`.
abstract interface class WebMidiPortHandle {
  // ...........................................................................
  /// Opens the port, like `MIDIPort.open()`.
  ///
  /// Throws a [WebMidiDomException] when the browser cannot open it.
  Future<void> open();

  /// Closes the port, like `MIDIPort.close()`.
  ///
  /// Throws a [WebMidiDomException] when the browser cannot close it.
  Future<void> close();

  // ...........................................................................
  /// The id the browser gives the port, `MIDIPort.id`.
  String get id;

  /// The name of the port, or null when the system does not tell.
  String? get name;

  /// The manufacturer of the port, or null when the system does not tell.
  String? get manufacturer;

  /// The version of the port's driver, or null when the system does not
  /// tell.
  String? get version;

  /// The device state, `connected` or `disconnected`.
  String get state;

  /// The connection state, `open`, `closed` or `pending`.
  String get connection;
}
