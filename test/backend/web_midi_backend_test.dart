// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';
import 'dart:typed_data';

import 'package:aud_midi_core/aud_midi_core.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:aud_midi_web/aud_midi_web.dart';
import 'package:test/test.dart';

void main() {
  late _Api api;
  late _Host host;
  late WebMidiBackend backend;
  late _Input keys;
  late _Output synth;

  const keysId = MidiPortId('webmidi:input:k1');
  const padsId = MidiPortId('webmidi:input:k2');
  const synthId = MidiPortId('webmidi:output:s1');
  const unknownId = MidiPortId('webmidi:output:x');

  setUp(() {
    api = _Api();
    host = _Host();
    backend = WebMidiBackend(api: api);
    keys = _Input('k1', name: 'Keys', manufacturer: 'Acme');
    synth = _Output('s1', name: 'Synth');
    api.access.inputs.add(keys);
    api.access.outputs.add(synth);
  });

  // The browser clock reads 1000 ms when the package clock reads 5 s, so a
  // browser time of t ms maps to the package time t * 1000 + 4000000 µs.

  MidiPortInfo keysInfo({MidiPortState state = MidiPortState.connected}) =>
      MidiPortInfo(
        id: keysId,
        deviceId: const MidiDeviceId('webmidi:input:k1'),
        name: 'Keys',
        manufacturer: 'Acme',
        direction: MidiDirection.input,
        state: state,
        capabilities: const MidiPortCapabilities(timestampsIn: true),
      );

  MidiPortInfo synthInfo({bool canClear = false}) => MidiPortInfo(
    id: synthId,
    deviceId: const MidiDeviceId('webmidi:output:s1'),
    name: 'Synth',
    direction: MidiDirection.output,
    capabilities: MidiPortCapabilities(
      scheduledSend: true,
      cancelPending: canClear,
    ),
  );

  MidiBytesPacket packet(String hex, {int at = 5000000}) =>
      MidiBytesPacket(bytes: MidiBytes.fromHex(hex), time: MidiTime(at));

  MidiDiagnostic diagnostic(
    MidiDiagnosticKind kind,
    String cause, {
    MidiPortId? port,
  }) => MidiDiagnostic(
    kind: kind,
    port: port,
    cause: cause,
    time: host.clock.now(),
  );

  Matcher throwsGone(MidiPortId port) =>
      throwsA(isA<MidiPortGone>().having((e) => e.port, 'port', port));

  Matcher throwsNative(String api, int code) => throwsA(
    isA<MidiNativeError>()
        .having((e) => e.api, 'api', api)
        .having((e) => e.code, 'code', code),
  );

  Matcher throwsUnsupported(String feature) => throwsA(
    isA<MidiUnsupported>().having((e) => e.feature, 'feature', feature),
  );

  const busy = WebMidiDomException(
    name: 'InvalidAccessError',
    message: 'busy',
    code: 15,
  );

  group('WebMidiBackend', () {
    group('WebMidiBackend(api, sysEx, software, resyncInterval)', () {
      test('requests neither SysEx nor software synthesizers by default', () {
        expect([
          backend.sysEx,
          backend.software,
          backend.resyncInterval,
        ], equals([false, false, const Duration(seconds: 10)]));
      });

      test('keeps the given options', () {
        final custom = WebMidiBackend(
          api: api,
          sysEx: true,
          software: true,
          resyncInterval: const Duration(seconds: 1),
        );

        expect([
          custom.sysEx,
          custom.software,
          custom.resyncInterval,
        ], equals([true, true, const Duration(seconds: 1)]));
      });

      test('uses the API of the platform, none on the VM', () {
        expect(
          WebMidiBackend().start(host),
          throwsUnsupported('Web MIDI on this platform'),
        );
      }, testOn: 'vm');
    });

    group('start(host)', () {
      test('requests the access with the options of the backend', () async {
        await WebMidiBackend(api: api, sysEx: true, software: true).start(host);

        expect(api.requests, equals([(sysEx: true, software: true)]));
      });

      test('lists the ports of the browser, inputs first', () async {
        await backend.start(host);

        expect(backend.ports, equals([keysInfo(), synthInfo()]));
      });

      test('keeps the details of the browser in the native map', () async {
        keys.version = '2.1';

        await backend.start(host);

        expect(
          backend.ports.map((port) => port.native),
          equals([
            {
              'id': 'k1',
              'version': '2.1',
              'state': 'connected',
              'connection': 'closed',
            },
            {
              'id': 's1',
              'version': null,
              'state': 'connected',
              'connection': 'closed',
            },
          ]),
        );
      });

      test('offers cancelPending where the browser has clear()', () async {
        synth.canClear = true;

        await backend.start(host);

        expect(backend.ports.last, equals(synthInfo(canClear: true)));
      });

      test('reports no events for the ports it finds', () async {
        await backend.start(host);

        expect(host.events, isEmpty);
      });

      test('watches the browser for hotplug', () async {
        await backend.start(host);

        expect(api.access.isWatched, isTrue);
      });

      test('throws a StateError when the backend runs already', () async {
        await backend.start(host);

        expect(
          backend.start(host),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'The Web MIDI backend runs already',
            ),
          ),
        );
      });

      for (final (isSecureContext, feature) in [
        (true, 'Web MIDI on this platform'),
        (false, 'Web MIDI outside a secure context (https or localhost)'),
      ]) {
        test('throws MidiUnsupported without Web MIDI, '
            'secure context: $isSecureContext', () async {
          api
            ..isAvailable = false
            ..isSecureContext = isSecureContext;

          await expectLater(backend.start(host), throwsUnsupported(feature));
          expect(api.requests, isEmpty);
        });
      }

      for (final (error, sysEx, permission, missing) in [
        ('NotAllowedError', false, MidiPermission.midi, {MidiPermission.midi}),
        (
          'SecurityError',
          true,
          MidiPermission.sysEx,
          {MidiPermission.midi, MidiPermission.sysEx},
        ),
      ]) {
        test('throws MidiPermissionDenied for $error, sysEx: $sysEx', () async {
          final denied = WebMidiBackend(api: api, sysEx: sysEx);
          api.rejection = WebMidiDomException(name: error, message: 'no');

          await expectLater(
            denied.start(host),
            throwsA(
              isA<MidiPermissionDenied>().having(
                (e) => e.permission,
                'permission',
                permission,
              ),
            ),
          );
          expect(denied.capabilities.missingPermissions, equals(missing));
        });
      }

      test('throws MidiUnsupported when the browser lacks MIDI', () async {
        api.rejection = const WebMidiDomException(
          name: 'NotSupportedError',
          message: 'No MIDI',
        );

        await expectLater(
          backend.start(host),
          throwsUnsupported('Web MIDI on this platform'),
        );
      });

      test('throws MidiNativeError for other failures, reports why', () async {
        api.rejection = const WebMidiDomException(
          name: 'InvalidStateError',
          message: 'Platform failed',
          code: 11,
        );

        await expectLater(
          backend.start(host),
          throwsNative('navigator.requestMIDIAccess', 11),
        );
        expect(
          host.diagnostics,
          equals([
            diagnostic(
              MidiDiagnosticKind.nativeError,
              'navigator.requestMIDIAccess: InvalidStateError: Platform failed',
            ),
          ]),
        );
      });

      test('can start again after a failure', () async {
        api.rejection = const WebMidiDomException(
          name: 'NotAllowedError',
          message: 'no',
        );
        await expectLater(
          backend.start(host),
          throwsA(isA<MidiPermissionDenied>()),
        );
        api.rejection = null;

        await backend.start(host);

        expect(backend.ports, equals([keysInfo(), synthInfo()]));
      });
    });

    group('stop()', () {
      test('does nothing when the backend does not run', () async {
        await backend.stop();

        expect(backend.ports, isEmpty);
      });

      test('stops watching, closes the open ports, forgets all', () async {
        await backend.start(host);
        await backend.openPort(keysId);
        await backend.openPort(synthId);

        await backend.stop();

        expect([api.access.isWatched, keys.isListened], equals([false, false]));
        expect([keys.closes, synth.closes], equals([1, 1]));
        expect(backend.ports, isEmpty);
      });

      test('reports a port that fails to close and goes on', () async {
        synth.closeError = busy;
        await backend.start(host);
        await backend.openPort(synthId);
        await backend.openPort(keysId);

        await backend.stop();

        expect(
          host.diagnostics,
          equals([
            diagnostic(
              MidiDiagnosticKind.nativeError,
              'MIDIPort.close: InvalidAccessError: busy',
              port: synthId,
            ),
          ]),
        );
        expect(keys.closes, 1);
      });

      test('lets the backend start again', () async {
        await backend.start(host);
        await backend.stop();

        await backend.start(host);

        expect(backend.ports, equals([keysInfo(), synthInfo()]));
      });
    });

    group('openPort(port)', () {
      test('opens an input that delivers its messages', () async {
        await backend.start(host);

        await backend.openPort(keysId);
        keys.receive('90 3c 64', 1500.5);

        expect(keys.opens, 1);
        expect(
          host.packets,
          equals([(keysId, packet('90 3c 64', at: 5500500))]),
        );
      });

      test('opens an output', () async {
        await backend.start(host);

        await backend.openPort(synthId);

        expect([synth.opens, synth.connection], equals([1, 'open']));
      });

      test('does nothing for an open port', () async {
        await backend.start(host);
        await backend.openPort(keysId);

        await backend.openPort(keysId);

        expect(keys.opens, 1);
      });

      test('throws MidiPortGone for an unknown port', () async {
        await backend.start(host);

        expect(backend.openPort(unknownId), throwsGone(unknownId));
      });

      test('throws MidiNativeError when the browser fails', () async {
        keys.openError = busy;
        await backend.start(host);

        await expectLater(
          backend.openPort(keysId),
          throwsNative('MIDIPort.open', 15),
        );
        expect(keys.isListened, isFalse);
        expect(
          host.diagnostics,
          equals([
            diagnostic(
              MidiDiagnosticKind.nativeError,
              'MIDIPort.open: InvalidAccessError: busy',
              port: keysId,
            ),
          ]),
        );
      });
    });

    group('closePort(port)', () {
      test('stops the delivery of an input and closes it', () async {
        await backend.start(host);
        await backend.openPort(keysId);

        await backend.closePort(keysId);
        keys.receive('90 3c 64', 1500);

        expect([keys.isListened, keys.closes], equals([false, 1]));
        expect(host.packets, isEmpty);
      });

      test('does nothing for a port that is not open', () async {
        await backend.start(host);

        await backend.closePort(synthId);

        expect(synth.closes, 0);
      });

      test('does nothing for an unknown port', () async {
        await backend.closePort(keysId);

        expect(keys.closes, 0);
      });

      test('throws MidiNativeError when the browser fails', () async {
        synth.closeError = busy;
        await backend.start(host);
        await backend.openPort(synthId);

        await expectLater(
          backend.closePort(synthId),
          throwsNative('MIDIPort.close', 15),
        );
        expect(
          host.diagnostics,
          equals([
            diagnostic(
              MidiDiagnosticKind.nativeError,
              'MIDIPort.close: InvalidAccessError: busy',
              port: synthId,
            ),
          ]),
        );
      });
    });

    group('messages of open inputs', () {
      for (final timeStamp in [0.0, -1.0, double.nan, double.infinity]) {
        test('carry the current time for the time stamp $timeStamp', () async {
          await backend.start(host);
          await backend.openPort(keysId);
          api.time = 1200;

          keys.receive('f8', timeStamp);

          expect(host.packets, equals([(keysId, packet('f8', at: 5200000))]));
        });
      }

      test('are dropped when empty', () async {
        await backend.start(host);
        await backend.openPort(keysId);

        keys.receive('', 1500);

        expect(host.packets, isEmpty);
      });

      test('measure the clock offset again after the interval', () async {
        await backend.start(host);
        await backend.openPort(keysId);
        host.clock.jumpTo(const MidiTime(20000000));

        api.time = 10999;
        keys.receive('f8', 10999);
        api.time = 11000;
        keys.receive('f8', 11000);

        expect(
          host.packets,
          equals([
            (keysId, packet('f8', at: 14999000)),
            (keysId, packet('f8', at: 20000000)),
          ]),
        );
      });
    });

    group('send(port, packet)', () {
      test('sends bytes that are due at once', () async {
        await backend.start(host);

        await backend.send(synthId, packet('90 3c 64', at: 4000000));
        await backend.send(synthId, packet('80 3c 00', at: 5000000));

        expect(synth.sent, equals(['90 3c 64 @ 0.0', '80 3c 00 @ 0.0']));
      });

      test('schedules bytes that are due later in the browser', () async {
        await backend.start(host);

        await backend.send(synthId, packet('90 3c 64', at: 5200000));

        expect(synth.sent, equals(['90 3c 64 @ 1200.0']));
      });

      test('sends nothing for an empty packet', () async {
        await backend.start(host);

        await backend.send(synthId, packet(''));

        expect([synth.sent, host.diagnostics], equals([isEmpty, isEmpty]));
      });

      test('reports bytes the browser would refuse', () async {
        await backend.start(host);

        await backend.send(synthId, packet('90 3c 64 3e 64'));

        expect(synth.sent, isEmpty);
        expect(
          host.diagnostics,
          equals([
            diagnostic(
              MidiDiagnosticKind.invalidData,
              'Data byte 0x3E at index 3 has no status byte; '
              'Web MIDI refuses running status',
              port: synthId,
            ),
          ]),
        );
      });

      test('reports System Exclusive without permission', () async {
        await backend.start(host);

        await backend.send(synthId, packet('f0 7e 7f f7'));

        expect(synth.sent, isEmpty);
        expect(
          host.diagnostics,
          equals([
            diagnostic(
              MidiDiagnosticKind.untranslatable,
              'System Exclusive at index 0 needs a MIDI access with sysEx '
              'enabled',
              port: synthId,
            ),
          ]),
        );
      });

      test('sends System Exclusive with permission', () async {
        api.access.sysExEnabled = true;
        await backend.start(host);

        await backend.send(synthId, packet('f0 7e 7f f7'));

        expect(synth.sent, equals(['f0 7e 7f f7 @ 0.0']));
      });

      test('reports when the browser refuses the bytes', () async {
        synth.sendError = const WebMidiDomException(
          name: 'InvalidStateError',
          message: 'Port is disconnected',
          code: 11,
        );
        await backend.start(host);

        await backend.send(synthId, packet('90 3c 64'));

        expect(
          host.diagnostics,
          equals([
            diagnostic(
              MidiDiagnosticKind.nativeError,
              'MIDIOutput.send: InvalidStateError: Port is disconnected',
              port: synthId,
            ),
          ]),
        );
      });

      test('throws MidiPortGone for an unknown port', () {
        expect(backend.send(synthId, packet('f8')), throwsGone(synthId));
      });

      test('throws an ArgumentError for an input', () async {
        await backend.start(host);

        expect(
          backend.send(keysId, packet('f8')),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              'Not an output port',
            ),
          ),
        );
      });

      test('throws MidiUnsupported for UMP', () async {
        await backend.start(host);

        expect(
          backend.send(
            synthId,
            MidiUmpPacket(words: [0x20903C64], time: MidiTime.zero),
          ),
          throwsUnsupported('UMP on Web MIDI ports'),
        );
      });
    });

    group('cancelPending(port)', () {
      test('clears what the output has not sent yet', () async {
        synth.canClear = true;
        await backend.start(host);

        await backend.cancelPending(synthId);

        expect(synth.clears, 1);
      });

      test('throws MidiUnsupported when the browser lacks clear()', () async {
        await backend.start(host);

        expect(
          backend.cancelPending(synthId),
          throwsUnsupported('MIDIOutput.clear() in this browser'),
        );
      });

      test('throws MidiNativeError when clear() fails', () async {
        synth
          ..canClear = true
          ..clearError = busy;
        await backend.start(host);

        await expectLater(
          backend.cancelPending(synthId),
          throwsNative('MIDIOutput.clear', 15),
        );
        expect(
          host.diagnostics,
          equals([
            diagnostic(
              MidiDiagnosticKind.nativeError,
              'MIDIOutput.clear: InvalidAccessError: busy',
              port: synthId,
            ),
          ]),
        );
      });

      test('throws MidiPortGone for an unknown port', () async {
        await backend.start(host);

        expect(backend.cancelPending(unknownId), throwsGone(unknownId));
      });

      test('throws an ArgumentError for an input', () async {
        await backend.start(host);

        expect(backend.cancelPending(keysId), throwsA(isA<ArgumentError>()));
      });
    });

    group('hotplug', () {
      test('reports ports that appear', () async {
        await backend.start(host);
        final pads = _Input('k2', name: 'Pads', manufacturer: 'Acme');

        api.access.inputs.add(pads);
        api.access.change();

        final padsInfo = MidiPortInfo(
          id: padsId,
          deviceId: const MidiDeviceId('webmidi:input:k2'),
          name: 'Pads',
          manufacturer: 'Acme',
          direction: MidiDirection.input,
          capabilities: const MidiPortCapabilities(timestampsIn: true),
        );
        expect(
          host.events,
          equals([
            [MidiPortAdded(port: padsInfo)],
          ]),
        );
        expect(
          backend.ports.map((port) => port.id),
          equals([keysId, padsId, synthId]),
        );
      });

      test('reports ports that change', () async {
        await backend.start(host);

        keys.state = 'disconnected';
        api.access.change();

        expect(
          host.events,
          equals([
            [
              MidiPortChanged(
                port: keysInfo(state: MidiPortState.disconnected),
                previous: keysInfo(),
              ),
            ],
          ]),
        );
      });

      test('reports ports that disappear and closes them', () async {
        await backend.start(host);
        await backend.openPort(keysId);

        api.access.inputs.clear();
        api.access.change();
        await pumpEventQueue();

        expect(
          host.events,
          equals([
            [MidiPortRemoved(port: keysInfo())],
          ]),
        );
        expect([keys.isListened, keys.closes], equals([false, 1]));
        expect(backend.ports, equals([synthInfo()]));
      });

      test('reports nothing when only the connection changed', () async {
        await backend.start(host);

        keys.connection = 'open';
        api.access.change();

        expect(host.events, isEmpty);
        expect(backend.ports.first.native['connection'], 'open');
      });

      test('reports a vanished port that fails to close', () async {
        keys.closeError = busy;
        await backend.start(host);
        await backend.openPort(keysId);

        api.access.inputs.clear();
        api.access.change();
        await pumpEventQueue();

        expect(
          host.diagnostics,
          equals([
            diagnostic(
              MidiDiagnosticKind.nativeError,
              'MIDIPort.close: InvalidAccessError: busy',
              port: keysId,
            ),
          ]),
        );
      });

      test('drops the failure of a close that ends after stop', () async {
        final gate = Completer<void>();
        keys
          ..closeGate = gate.future
          ..closeError = busy;
        await backend.start(host);
        await backend.openPort(keysId);
        api.access.inputs.clear();
        api.access.change();

        await backend.stop();
        gate.complete();
        await pumpEventQueue();

        expect([keys.closes, host.diagnostics], equals([1, isEmpty]));
      });

      test('measures the clock offset again', () async {
        await backend.start(host);
        await backend.openPort(keysId);
        host.clock.jumpTo(const MidiTime(7000000));
        api.time = 1500;

        api.access.change();
        keys.receive('f8', 1500);

        expect(host.packets, equals([(keysId, packet('f8', at: 7000000))]));
      });
    });

    group('name', () {
      test('is the backend name', () {
        expect(backend.name, 'webmidi');
      });
    });

    group('capabilities', () {
      test('offer scheduling in the browser and nothing else', () {
        expect(
          backend.capabilities,
          equals(MidiCapabilities(scheduling: MidiSchedulingSupport.hardware)),
        );
      });

      for (final (granted, missing) in [
        (false, {MidiPermission.sysEx}),
        (true, <MidiPermission>{}),
      ]) {
        test(
          'name SysEx as missing unless granted, granted: $granted',
          () async {
            api.access.sysExEnabled = granted;

            await backend.start(host);

            expect(backend.capabilities.missingPermissions, equals(missing));
          },
        );
      }
    });

    group('ports', () {
      test('is empty before start', () {
        expect(backend.ports, isEmpty);
      });
    });

    group('virtualPorts, bluetooth, network', () {
      test('are null, Web MIDI has none of them', () {
        expect([
          backend.virtualPorts,
          backend.bluetooth,
          backend.network,
        ], equals([null, null, null]));
      });
    });

    group('backendName', () {
      test('is the prefix of the port ids', () {
        expect(WebMidiBackend.backendName, 'webmidi');
      });
    });
  });
}

// #############################################################################
/// Records what the backend reports.
final class _Host implements MidiBackendHost {
  @override
  final MidiFakeClock clock = MidiFakeClock(start: const MidiTime(5000000));

  final events = <List<MidiPortEvent>>[];
  final packets = <(MidiPortId, MidiPacket)>[];
  final diagnostics = <MidiDiagnostic>[];

  @override
  void portsChanged(List<MidiPortEvent> events) => this.events.add(events);

  @override
  void received(MidiPortId port, MidiPacket packet) =>
      packets.add((port, packet));

  @override
  void diagnostic(MidiDiagnostic diagnostic) => diagnostics.add(diagnostic);
}

// #############################################################################
/// A browser with a settable clock and access.
final class _Api implements WebMidiApi {
  final access = _Access();
  final requests = <({bool sysEx, bool software})>[];
  WebMidiDomException? rejection;
  double time = 1000;

  @override
  bool isAvailable = true;

  @override
  bool isSecureContext = true;

  @override
  Future<WebMidiAccess> requestAccess({
    required bool sysEx,
    required bool software,
  }) async {
    requests.add((sysEx: sysEx, software: software));
    if (rejection case final rejection?) throw rejection;
    return access;
  }

  @override
  double now() => time;
}

// #############################################################################
/// The ports of the browser, changed by the tests.
final class _Access implements WebMidiAccess {
  @override
  final List<_Input> inputs = [];

  @override
  final List<_Output> outputs = [];

  @override
  bool sysExEnabled = false;

  @override
  Stream<void> get stateChanges => _changes.stream;

  /// Whether the backend listens for state changes.
  bool get isWatched => _changes.hasListener;

  /// Fires a `statechange` event.
  void change() => _changes.add(null);

  final _changes = StreamController<void>.broadcast(sync: true);
}

// #############################################################################
/// What the fake inputs and outputs share.
abstract base class _Port implements WebMidiPortHandle {
  _Port(this.id, {this.name, this.manufacturer});

  @override
  final String id;

  @override
  String? name;

  @override
  String? manufacturer;

  @override
  String? version;

  @override
  String state = 'connected';

  @override
  String connection = 'closed';

  WebMidiDomException? openError;
  WebMidiDomException? closeError;
  Future<void>? closeGate;
  var opens = 0;
  var closes = 0;

  @override
  Future<void> open() async {
    opens++;
    if (openError case final error?) throw error;
    connection = 'open';
  }

  @override
  Future<void> close() async {
    closes++;
    await closeGate;
    if (closeError case final error?) throw error;
    connection = 'closed';
  }
}

// #############################################################################
/// An input whose messages the tests trigger.
final class _Input extends _Port implements WebMidiInputHandle {
  _Input(super.id, {super.name, super.manufacturer});

  @override
  Stream<WebMidiMessage> get messages => _messages.stream;

  /// Whether the backend listens for messages.
  bool get isListened => _messages.hasListener;

  /// Delivers the bytes [hex] received at [timeStamp].
  void receive(String hex, double timeStamp) =>
      _messages.add((data: MidiBytes.fromHex(hex).bytes, timeStamp: timeStamp));

  final _messages = StreamController<WebMidiMessage>.broadcast(sync: true);
}

// #############################################################################
/// An output that records what it sends.
final class _Output extends _Port implements WebMidiOutputHandle {
  _Output(super.id, {super.name});

  final sent = <String>[];
  WebMidiDomException? sendError;
  WebMidiDomException? clearError;
  var clears = 0;

  @override
  bool canClear = false;

  @override
  void send(Uint8List data, {double timestamp = 0}) {
    if (sendError case final error?) throw error;
    sent.add('${MidiBytes(data).toHex()} @ $timestamp');
  }

  @override
  void clear() {
    clears++;
    if (clearError case final error?) throw error;
  }
}
