// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';
import 'dart:typed_data';

import 'package:aud_midi_core/aud_midi_core.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';

import '../api/web_midi_access.dart';
import '../api/web_midi_api.dart';
import '../api/web_midi_dom_exception.dart';
import '../api/web_midi_input_handle.dart';
import '../api/web_midi_message.dart';
import '../api/web_midi_output_handle.dart';
import '../api/web_midi_platform_api.dart'
    if (dart.library.js_interop) '../browser/web_midi_browser_api.dart'
    show webMidiPlatformApi;
import '../api/web_midi_port_handle.dart';
import '../api/web_midi_unavailable_api.dart';
import 'web_midi_message_validator.dart';

// #############################################################################
/// The MIDI ports of the browser, through the Web MIDI API.
///
/// Every Web MIDI port becomes a MIDI 1.0 byte port on a synthetic device of
/// its own; MIDI 2.0 runs through the translation of the engine. Inputs
/// carry the browser's receive time, outputs schedule sends in the browser
/// (`MIDIOutput.send(data, timestamp)`) and cancel them with
/// `MIDIOutput.clear()` where the browser implements it. Hotplug arrives
/// through `onstatechange`. Web MIDI has no virtual ports and no network
/// sessions; Bluetooth devices show up only when the operating system
/// paired them, as ordinary ports.
///
/// [start] makes the browser ask the user for permission; System Exclusive
/// ([sysEx]) needs a stronger one. Web MIDI requires a secure context
/// (https or localhost) and, inside an iframe, the permission policy
/// `midi`.
final class WebMidiBackend implements MidiBackend {
  /// Creates the backend.
  ///
  /// - [api] the Web MIDI API; by default the browser's in the browser and
  ///   a [WebMidiUnavailableApi] elsewhere, where [start] throws
  ///   [MidiUnsupported]
  /// - [sysEx] requests System Exclusive messages
  /// - [software] requests the software synthesizers of the system, too
  /// - [resyncInterval] how often the offset between the browser clock and
  ///   the package clock is measured again
  WebMidiBackend({
    WebMidiApi? api,
    this.sysEx = false,
    this.software = false,
    this.resyncInterval = const Duration(seconds: 10),
  }) : _api = api ?? webMidiPlatformApi();

  // ...........................................................................
  /// Requests access to the MIDI ports of the browser and lists them.
  ///
  /// Throws [MidiUnsupported] when the browser lacks Web MIDI or the page a
  /// secure context, [MidiPermissionDenied] when the user or a permission
  /// policy refuses access — for [MidiPermission.sysEx] when [sysEx] was
  /// requested, else for [MidiPermission.midi] — and [MidiNativeError] for
  /// any other failure. Throws a [StateError] when the backend runs already.
  @override
  Future<void> start(MidiBackendHost host) async {
    if (_host != null) throw StateError('The Web MIDI backend runs already');
    _checkAvailable();
    _host = host;
    try {
      _begin(await _api.requestAccess(sysEx: sysEx, software: software));
    } on WebMidiDomException catch (error) {
      final exception = _accessError(error);
      _host = null;
      throw exception;
    }
  }

  /// Stops watching for hotplug, closes the open ports and forgets them.
  @override
  Future<void> stop() async {
    if (_access == null) return;
    await _stateChanges?.cancel();
    _stateChanges = null;
    for (final port in [..._open.keys]) {
      await _closeReporting(port, _ports[port]!.handle);
    }
    _ports.clear();
    _access = null;
    _clock = null;
    _host = null;
  }

  // ...........................................................................
  /// Opens [port]; an input starts to deliver its messages.
  ///
  /// Throws [MidiPortGone] for an unknown port and [MidiNativeError] when
  /// the browser cannot open it.
  @override
  Future<void> openPort(MidiPortId port) async {
    final handle = _handle(port);
    if (_open.containsKey(port)) return;
    _open[port] = handle is WebMidiInputHandle
        ? handle.messages.listen((message) => _receive(port, message))
        : null;
    try {
      await handle.open();
    } on WebMidiDomException catch (error) {
      await _open.remove(port)?.cancel();
      throw _nativeError('MIDIPort.open', error, port: port);
    }
  }

  /// Closes [port]; does nothing when it is not open.
  ///
  /// Throws [MidiNativeError] when the browser cannot close it.
  @override
  Future<void> closePort(MidiPortId port) async {
    final entry = _ports[port];
    if (entry == null || !_open.containsKey(port)) return;
    final error = await _close(port, entry.handle);
    if (error != null) throw _nativeError('MIDIPort.close', error, port: port);
  }

  // ...........................................................................
  /// Sends the bytes of [packet] to the output [port], scheduled by the
  /// browser for the packet's time.
  ///
  /// Bytes the browser would refuse — running status, undefined status
  /// bytes, incomplete messages, System Exclusive that is split or not
  /// permitted — and failures of the browser become diagnostics instead.
  /// Throws [MidiPortGone] for an unknown port, an [ArgumentError] for an
  /// input port and [MidiUnsupported] for a [MidiUmpPacket].
  @override
  Future<void> send(MidiPortId port, MidiPacket packet) async {
    final output = _output(port);
    final bytes = _bytesOf(packet);
    if (bytes.isEmpty || _refuses(port, bytes)) return;
    try {
      output.send(bytes, timestamp: _browserTime(packet.time));
    } on WebMidiDomException catch (error) {
      _report(
        kind: MidiDiagnosticKind.nativeError,
        port: port,
        cause: 'MIDIOutput.send: $error',
      );
    }
  }

  /// Discards what the output [port] has not sent yet, with
  /// `MIDIOutput.clear()`.
  ///
  /// Throws [MidiPortGone] for an unknown port, an [ArgumentError] for an
  /// input port, [MidiUnsupported] when the browser lacks `clear()` (see
  /// [MidiPortCapabilities.cancelPending]) and [MidiNativeError] when it
  /// fails.
  @override
  Future<void> cancelPending(MidiPortId port) async {
    final output = _output(port);
    if (!output.canClear) {
      throw const MidiUnsupported('MIDIOutput.clear() in this browser');
    }
    try {
      output.clear();
    } on WebMidiDomException catch (error) {
      throw _nativeError('MIDIOutput.clear', error, port: port);
    }
  }

  // ...........................................................................
  @override
  String get name => backendName;

  /// What Web MIDI offers: ports with scheduling in the browser, nothing
  /// else; [MidiCapabilities.missingPermissions] names the permissions the
  /// browser refused or did not grant.
  @override
  MidiCapabilities get capabilities => MidiCapabilities(
    scheduling: MidiSchedulingSupport.hardware,
    missingPermissions: _missingPermissions,
  );

  @override
  List<MidiPortInfo> get ports => [
    for (final entry in _ports.values) entry.info,
  ];

  /// Null: Web MIDI cannot create ports.
  @override
  MidiVirtualPortsBackend? get virtualPorts => null;

  /// Null: Web MIDI cannot scan for Bluetooth devices; devices the
  /// operating system paired appear as ordinary ports.
  @override
  MidiBluetoothBackend? get bluetooth => null;

  /// Null: Web MIDI has no network sessions.
  @override
  MidiNetworkBackend? get network => null;

  // ...........................................................................
  /// Whether [start] requests System Exclusive messages.
  final bool sysEx;

  /// Whether [start] requests the software synthesizers of the system, too.
  final bool software;

  /// How often the offset between the browser clock and the package clock
  /// is measured again; hotplug measures it, too.
  final Duration resyncInterval;

  // ...........................................................................
  /// The name of the backend and the prefix of its port ids.
  static const String backendName = 'webmidi';

  // ...........................................................................
  final WebMidiApi _api;
  MidiBackendHost? _host;
  WebMidiAccess? _access;
  MidiClockMapper? _clock;
  double _syncedAt = 0;
  Set<MidiPermission> _missingPermissions = const {};
  StreamSubscription<void>? _stateChanges;

  /// The listed ports in the browser's order, inputs first.
  final Map<MidiPortId, _WebPort> _ports = {};

  /// The open ports, with the message subscription of an input.
  final Map<MidiPortId, StreamSubscription<WebMidiMessage>?> _open = {};

  /// Throws [MidiUnsupported] when the browser lacks Web MIDI.
  void _checkAvailable() {
    if (_api.isAvailable) return;
    throw MidiUnsupported(
      _api.isSecureContext
          ? 'Web MIDI on this platform'
          : 'Web MIDI outside a secure context (https or localhost)',
    );
  }

  /// Returns the exception for the rejected access request [error].
  MidiException _accessError(WebMidiDomException error) {
    switch (error.name) {
      case 'NotAllowedError' || 'SecurityError':
        _missingPermissions = {
          MidiPermission.midi,
          if (sysEx) MidiPermission.sysEx,
        };
        return MidiPermissionDenied(
          sysEx ? MidiPermission.sysEx : MidiPermission.midi,
        );
      case 'NotSupportedError':
        return const MidiUnsupported('Web MIDI on this platform');
      default:
        return _nativeError('navigator.requestMIDIAccess', error);
    }
  }

  /// Starts to work with the granted [access].
  void _begin(WebMidiAccess access) {
    _access = access;
    _clock = MidiClockMapper(clock: _host!.clock, nativeNow: _nativeMicros);
    _syncedAt = _api.now();
    _missingPermissions = {if (!access.sysExEnabled) MidiPermission.sysEx};
    _rescan();
    _stateChanges = access.stateChanges.listen((_) => _onStateChange());
  }

  /// Measures the clock offset again and reports what hotplug changed.
  void _onStateChange() {
    _resync(_api.now());
    final events = _rescan();
    if (events.isNotEmpty) _host!.portsChanged(events);
  }

  /// Lists the ports of the access again and returns what changed; open
  /// ports that disappeared are closed.
  List<MidiPortEvent> _rescan() {
    final previous = Map.of(_ports);
    _ports.clear();
    final events = <MidiPortEvent>[];
    for (final entry in _list(_access!)) {
      _ports[entry.info.id] = entry;
      final old = previous.remove(entry.info.id)?.info;
      if (old == null) {
        events.add(MidiPortAdded(port: entry.info));
      } else if (old != entry.info) {
        events.add(MidiPortChanged(port: entry.info, previous: old));
      }
    }
    for (final gone in previous.values) {
      if (_open.containsKey(gone.info.id)) {
        unawaited(_closeReporting(gone.info.id, gone.handle));
      }
      events.add(MidiPortRemoved(port: gone.info));
    }
    return events;
  }

  /// Returns the ports of [access], inputs first.
  List<_WebPort> _list(WebMidiAccess access) => [
    for (final handle in [...access.inputs, ...access.outputs])
      (info: _info(handle), handle: handle),
  ];

  /// Describes the port behind [handle].
  MidiPortInfo _info(WebMidiPortHandle handle) {
    final isOutput = handle is WebMidiOutputHandle;
    final direction = isOutput ? MidiDirection.output : MidiDirection.input;
    final nativeId = '${direction.name}:${handle.id}';
    return MidiPortInfo(
      id: MidiPortId.of(backend: name, nativeId: nativeId),
      deviceId: MidiDeviceId.of(backend: name, nativeId: nativeId),
      name: handle.name ?? '',
      manufacturer: handle.manufacturer ?? '',
      direction: direction,
      state: handle.state == 'disconnected'
          ? MidiPortState.disconnected
          : MidiPortState.connected,
      capabilities: isOutput
          ? MidiPortCapabilities(
              scheduledSend: true,
              cancelPending: handle.canClear,
            )
          : const MidiPortCapabilities(timestampsIn: true),
      native: {
        'id': handle.id,
        'version': handle.version,
        'state': handle.state,
        'connection': handle.connection,
      },
    );
  }

  /// Returns the handle of [port] or throws [MidiPortGone].
  WebMidiPortHandle _handle(MidiPortId port) =>
      _ports[port]?.handle ?? (throw MidiPortGone(port));

  /// Returns the handle of the output [port].
  WebMidiOutputHandle _output(MidiPortId port) {
    final handle = _handle(port);
    if (handle is! WebMidiOutputHandle) {
      throw ArgumentError.value(port, 'port', 'Not an output port');
    }
    return handle;
  }

  /// Stops the delivery of the open [port] and closes it; returns the
  /// browser's error, if any.
  Future<WebMidiDomException?> _close(
    MidiPortId port,
    WebMidiPortHandle handle,
  ) async {
    await _open.remove(port)?.cancel();
    try {
      await handle.close();
      return null;
    } on WebMidiDomException catch (error) {
      return error;
    }
  }

  /// Closes the open [port] and reports a failure as diagnostic.
  Future<void> _closeReporting(
    MidiPortId port,
    WebMidiPortHandle handle,
  ) async {
    final error = await _close(port, handle);
    if (error == null) return;
    _report(
      kind: MidiDiagnosticKind.nativeError,
      port: port,
      cause: 'MIDIPort.close: $error',
    );
  }

  /// Delivers the [message] of the input [port] to the host.
  void _receive(MidiPortId port, WebMidiMessage message) {
    if (message.data.isEmpty) return;
    _host!.received(
      port,
      MidiBytesPacket(
        bytes: MidiBytes(message.data),
        time: _packageTime(message.timeStamp),
      ),
    );
  }

  /// Returns the bytes of [packet]; Web MIDI ports take no UMP.
  Uint8List _bytesOf(MidiPacket packet) => switch (packet) {
    MidiBytesPacket(:final bytes) => bytes.bytes,
    MidiUmpPacket() => throw const MidiUnsupported('UMP on Web MIDI ports'),
  };

  /// Whether the browser would refuse [bytes]; reports why.
  bool _refuses(MidiPortId port, Uint8List bytes) {
    final validator = WebMidiMessageValidator(
      sysExEnabled: _access!.sysExEnabled,
    );
    final problem = validator.check(bytes);
    if (problem == null) return false;
    _report(kind: problem.kind, port: port, cause: problem.cause);
    return true;
  }

  /// Converts the browser time [timeStamp] in milliseconds to the package
  /// clock; a missing time stamp counts as now.
  MidiTime _packageTime(double timeStamp) {
    _resyncIfDue();
    final isKnown = timeStamp.isFinite && timeStamp > 0;
    return _clock!.toPackage(isKnown ? _micros(timeStamp) : _nativeMicros());
  }

  /// Converts the package time [due] to the browser's clock in
  /// milliseconds; 0, which means now, when it is not in the future.
  double _browserTime(MidiTime due) {
    _resyncIfDue();
    final timestamp = _clock!.toNative(due) / 1000;
    return timestamp > _api.now() ? timestamp : 0;
  }

  /// Measures the clock offset again when [resyncInterval] passed.
  void _resyncIfDue() {
    final now = _api.now();
    if (now - _syncedAt < resyncInterval.inMicroseconds / 1000) return;
    _resync(now);
  }

  /// Measures the clock offset again at the browser time [now].
  void _resync(double now) {
    _clock!.resync();
    _syncedAt = now;
  }

  /// Reads the browser clock in microseconds.
  int _nativeMicros() => _micros(_api.now());

  /// Reports a diagnostic of [kind] for [port] with [cause].
  void _report({
    required MidiDiagnosticKind kind,
    MidiPortId? port,
    required String cause,
  }) {
    final host = _host;
    if (host == null) return;
    host.diagnostic(
      MidiDiagnostic(
        kind: kind,
        port: port,
        cause: cause,
        time: host.clock.now(),
      ),
    );
  }

  /// Reports the failed browser call [api] and returns the exception for it.
  MidiNativeError _nativeError(
    String api,
    WebMidiDomException error, {
    MidiPortId? port,
  }) {
    _report(
      kind: MidiDiagnosticKind.nativeError,
      port: port,
      cause: '$api: $error',
    );
    return MidiNativeError(api: api, code: error.code);
  }

  /// Converts [milliseconds] to whole microseconds.
  static int _micros(double milliseconds) => (milliseconds * 1000).round();
}

// #############################################################################
/// A listed port: its description and its browser handle.
typedef _WebPort = ({MidiPortInfo info, WebMidiPortHandle handle});
