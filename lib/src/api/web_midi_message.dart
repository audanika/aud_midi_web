// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

// #############################################################################
/// One `midimessage` event of a Web MIDI input.
///
/// [data] holds one complete MIDI message, [timeStamp] the time it was
/// received, in milliseconds on the clock of `performance.now()`.
typedef WebMidiMessage = ({Uint8List data, double timeStamp});
