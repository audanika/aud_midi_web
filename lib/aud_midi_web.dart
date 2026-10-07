// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

/// The browser backend of the aud_midi family: the MIDI ports of the Web
/// MIDI API as byte ports, behind a small Dart interface to the browser.
library;

export 'src/api/web_midi_access.dart';
export 'src/api/web_midi_api.dart';
export 'src/api/web_midi_dom_exception.dart';
export 'src/api/web_midi_input_handle.dart';
export 'src/api/web_midi_message.dart';
export 'src/api/web_midi_output_handle.dart';
export 'src/api/web_midi_port_handle.dart';
export 'src/api/web_midi_unavailable_api.dart';
export 'src/backend/web_midi_backend.dart';
export 'src/backend/web_midi_message_validator.dart';
