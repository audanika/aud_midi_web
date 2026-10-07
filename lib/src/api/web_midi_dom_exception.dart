// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

// #############################################################################
/// A JavaScript error the Web MIDI API threw or rejected a promise with,
/// usually a `DOMException`.
final class WebMidiDomException implements Exception {
  /// Creates the exception for the error [name] with the browser's
  /// [message] and the legacy DOMException [code].
  const WebMidiDomException({
    required this.name,
    required this.message,
    this.code = 0,
  });

  // ...........................................................................
  @override
  String toString() => '$name: $message';

  // ...........................................................................
  /// The name of the error, e.g. `NotAllowedError` or `TypeError`.
  final String name;

  /// The message of the browser.
  final String message;

  /// The legacy numeric code of a DOMException, 0 when there is none.
  final int code;
}
