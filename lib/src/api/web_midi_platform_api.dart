// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'web_midi_api.dart';
import 'web_midi_unavailable_api.dart';

// #############################################################################
/// Returns the Web MIDI API of the platform the code runs on.
///
/// This variant serves platforms without `dart:js_interop`, e.g. the Dart
/// VM, and returns a [WebMidiUnavailableApi]. In the browser a conditional
/// import replaces it with the variant of `browser/web_midi_browser_api.dart`,
/// which returns the browser's API.
WebMidiApi webMidiPlatformApi() => const WebMidiUnavailableApi();
