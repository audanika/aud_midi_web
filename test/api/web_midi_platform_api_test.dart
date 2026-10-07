// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_web/aud_midi_web.dart';
// The platform selection is deliberately not exported: the backend uses it.
import 'package:aud_midi_web/src/api/web_midi_platform_api.dart';
import 'package:test/test.dart';

void main() {
  group('webMidiPlatformApi()', () {
    test('returns the unavailable API outside the browser', () {
      expect(webMidiPlatformApi(), isA<WebMidiUnavailableApi>());
    });
  });
}
