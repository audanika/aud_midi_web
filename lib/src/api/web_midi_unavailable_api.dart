// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'web_midi_access.dart';
import 'web_midi_api.dart';
import 'web_midi_dom_exception.dart';

// #############################################################################
/// The Web MIDI API where there is none, e.g. on the Dart VM.
///
/// `WebMidiBackend` uses it outside the browser, so starting the backend
/// there fails with `MidiUnsupported`.
final class WebMidiUnavailableApi implements WebMidiApi {
  /// Creates the unavailable API.
  const WebMidiUnavailableApi();

  // ...........................................................................
  /// Throws a [WebMidiDomException] named `NotSupportedError`, like a
  /// browser without MIDI support.
  @override
  Future<WebMidiAccess> requestAccess({
    required bool sysEx,
    required bool software,
  }) async => throw const WebMidiDomException(
    name: 'NotSupportedError',
    message: 'Web MIDI is not available on this platform',
  );

  // ...........................................................................
  /// Returns the milliseconds since the first call, from a monotonic
  /// stopwatch.
  @override
  double now() => _stopwatch.elapsedMicroseconds / 1000;

  // ...........................................................................
  @override
  bool get isAvailable => false;

  /// Whether the page runs in a secure context: true, because no page
  /// restricts Web MIDI here; the browser itself is missing.
  @override
  bool get isSecureContext => true;

  // ...........................................................................
  static final Stopwatch _stopwatch = Stopwatch()..start();
}
