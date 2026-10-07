// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

// coverage:ignore-file
// Browser-only JS interop through package:web: the Dart VM cannot load this
// file. test/browser/web_midi_browser_api_test.dart runs it in Chrome.

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart';

import '../api/web_midi_access.dart';
import '../api/web_midi_api.dart';
import '../api/web_midi_dom_exception.dart';
import '../api/web_midi_input_handle.dart';
import '../api/web_midi_message.dart';
import '../api/web_midi_output_handle.dart';
import '../api/web_midi_port_handle.dart';

// #############################################################################
/// Returns the Web MIDI API of the platform the code runs on: in the
/// browser, a [WebMidiBrowserApi].
WebMidiApi webMidiPlatformApi() => const WebMidiBrowserApi();

// #############################################################################
/// The browser's Web MIDI API through `package:web`.
///
/// A thin adapter: it forwards every call to the browser and turns
/// JavaScript errors into [WebMidiDomException]s; all decisions are made by
/// `WebMidiBackend`.
final class WebMidiBrowserApi implements WebMidiApi {
  /// Creates the adapter for the current page.
  const WebMidiBrowserApi();

  // ...........................................................................
  @override
  Future<WebMidiAccess> requestAccess({
    required bool sysEx,
    required bool software,
  }) async {
    final options = MIDIOptions(sysex: sysEx, software: software);
    final access = await _guardAsync(
      () => window.navigator.requestMIDIAccess(options).toDart,
    );
    return _BrowserAccess(access);
  }

  // ...........................................................................
  @override
  double now() => _performanceNow();

  // ...........................................................................
  @override
  bool get isAvailable {
    final navigator = globalContext['navigator'];
    if (navigator == null || !navigator.isA<JSObject>()) return false;
    return (navigator as JSObject).has('requestMIDIAccess');
  }

  @override
  bool get isSecureContext =>
      globalContext['isSecureContext'].dartify() == true;
}

// #############################################################################
/// Reads `performance.now()`.
@JS('performance.now')
external double _performanceNow();

// #############################################################################
/// Iterates the ports of a `MIDIInputMap` or `MIDIOutputMap`, both
/// maplike.
extension on JSObject {
  external void forEach(JSFunction callback);
}

// #############################################################################
/// Sends a typed array, which `sequence<octet>` accepts without copying it
/// into a JavaScript array first.
extension on MIDIOutput {
  @JS('send')
  external void sendBytes(JSUint8Array data, double timestamp);
}

// #############################################################################
/// The granted `MIDIAccess`.
final class _BrowserAccess implements WebMidiAccess {
  _BrowserAccess(this._access);

  // ...........................................................................
  @override
  List<WebMidiInputHandle> get inputs {
    final result = <WebMidiInputHandle>[];
    _access.inputs.forEach(
      ((MIDIInput port, JSAny? _, JSAny? _) {
        result.add(_BrowserInput(port));
      }).toJS,
    );
    return result;
  }

  @override
  List<WebMidiOutputHandle> get outputs {
    final result = <WebMidiOutputHandle>[];
    _access.outputs.forEach(
      ((MIDIOutput port, JSAny? _, JSAny? _) {
        result.add(_BrowserOutput(port));
      }).toJS,
    );
    return result;
  }

  @override
  bool get sysExEnabled => _access.sysexEnabled;

  @override
  Stream<void> get stateChanges {
    late final StreamController<void> controller;
    controller = StreamController<void>(
      sync: true,
      onListen: () => _access.onstatechange = ((Event _) {
        controller.add(null);
      }).toJS,
      onCancel: () => _access.onstatechange = null,
    );
    return controller.stream;
  }

  // ...........................................................................
  final MIDIAccess _access;
}

// #############################################################################
/// What inputs and outputs share.
abstract base class _BrowserPort implements WebMidiPortHandle {
  _BrowserPort(this._port);

  // ...........................................................................
  @override
  Future<void> open() => _guardAsync(() => _port.open().toDart);

  @override
  Future<void> close() => _guardAsync(() => _port.close().toDart);

  // ...........................................................................
  @override
  String get id => _port.id;

  @override
  String? get name => _port.name;

  @override
  String? get manufacturer => _port.manufacturer;

  @override
  String? get version => _port.version;

  @override
  String get state => _port.state;

  @override
  String get connection => _port.connection;

  // ...........................................................................
  final MIDIPort _port;
}

// #############################################################################
/// A `MIDIInput`.
final class _BrowserInput extends _BrowserPort implements WebMidiInputHandle {
  _BrowserInput(this._input) : super(_input);

  // ...........................................................................
  @override
  Stream<WebMidiMessage> get messages {
    late final StreamController<WebMidiMessage> controller;
    controller = StreamController<WebMidiMessage>(
      sync: true,
      onListen: () => _input.onmidimessage = ((MIDIMessageEvent event) {
        controller.add((
          data: event.data?.toDart ?? Uint8List(0),
          timeStamp: event.timeStamp,
        ));
      }).toJS,
      onCancel: () => _input.onmidimessage = null,
    );
    return controller.stream;
  }

  // ...........................................................................
  final MIDIInput _input;
}

// #############################################################################
/// A `MIDIOutput`.
final class _BrowserOutput extends _BrowserPort implements WebMidiOutputHandle {
  _BrowserOutput(this._output) : super(_output);

  // ...........................................................................
  @override
  void send(Uint8List data, {double timestamp = 0}) =>
      _guard(() => _output.sendBytes(data.toJS, timestamp));

  @override
  void clear() => _guard(() => _output.clear());

  // ...........................................................................
  @override
  bool get canClear => _output.has('clear');

  // ...........................................................................
  final MIDIOutput _output;
}

// #############################################################################
/// Runs the browser call [call] and rethrows its errors as
/// [WebMidiDomException]s.
void _guard(void Function() call) {
  try {
    call();
  } catch (error, stackTrace) {
    Error.throwWithStackTrace(_domException(error), stackTrace);
  }
}

// #############################################################################
/// Awaits the browser call [call] and rethrows its errors as
/// [WebMidiDomException]s.
Future<T> _guardAsync<T>(Future<T> Function() call) async {
  try {
    return await call();
  } catch (error, stackTrace) {
    Error.throwWithStackTrace(_domException(error), stackTrace);
  }
}

// #############################################################################
/// Reads name, message and code of the JavaScript [error].
///
/// dart2js turns a JavaScript `TypeError` into a Dart error without these
/// properties, e.g. `Error: Failed to execute 'send' on 'MIDIOutput': …`;
/// its text without the prefix becomes the message.
WebMidiDomException _domException(Object error) {
  final value = error.jsify();
  if (value == null || !value.isA<JSObject>()) {
    const prefix = 'Error: ';
    final text = '$error';
    return WebMidiDomException(
      name: 'Error',
      message: text.startsWith(prefix) ? text.substring(prefix.length) : text,
    );
  }
  final object = value as JSObject;
  final name = object['name'].dartify();
  final message = object['message'].dartify();
  final code = object['code'].dartify();
  return WebMidiDomException(
    name: name is String ? name : 'Error',
    message: message is String ? message : '$error',
    code: code is num ? code.toInt() : 0,
  );
}
