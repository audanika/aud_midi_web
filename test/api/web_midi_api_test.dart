// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_web/aud_midi_web.dart';
import 'package:test/test.dart';

void main() {
  group('WebMidiApi', () {
    test('is implemented by the API of platforms without a browser', () {
      const WebMidiApi api = WebMidiUnavailableApi();

      expect([api.isAvailable, api.isSecureContext], equals([false, true]));
    });
  });
}
