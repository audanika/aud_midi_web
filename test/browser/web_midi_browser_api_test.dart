// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

// Runs in Chrome only: dart test -P browser (see dart_test.yaml).
@TestOn('browser')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:aud_midi_core/aud_midi_core.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:aud_midi_web/aud_midi_web.dart';
// The adapter is deliberately not exported: only web compilers load it.
import 'package:aud_midi_web/src/browser/web_midi_browser_api.dart';
import 'package:test/test.dart';

void main() {
  const api = WebMidiBrowserApi();
  const loopbackName = 'aud_midi_web loopback';
  const permissionErrors = ['NotAllowedError', 'SecurityError'];

  Future<WebMidiAccess?> grantedAccess() async {
    try {
      return await api.requestAccess(sysEx: false, software: false);
    } on WebMidiDomException catch (error) {
      expect(error.name, isIn(permissionErrors));
      markTestSkipped('The browser denied the MIDI permission');
      return null;
    }
  }

  group('webMidiPlatformApi()', () {
    test('returns the browser API in the browser', () {
      expect(webMidiPlatformApi(), isA<WebMidiBrowserApi>());
    });
  });

  group('WebMidiBrowserApi', () {
    group('requestAccess(sysEx, software)', () {
      for (final sysEx in [false, true]) {
        test('grants access or rejects it, sysEx: $sysEx', () async {
          try {
            final access = await api.requestAccess(
              sysEx: sysEx,
              software: false,
            );

            expect(access.sysExEnabled, sysEx);
          } on WebMidiDomException catch (error) {
            expect(error.name, isIn(permissionErrors));
            expect(error.message, isNotEmpty);
          }
        });
      }
    });

    group('now()', () {
      test('runs in milliseconds like performance.now()', () async {
        final first = api.now();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final elapsed = api.now() - first;

        expect(first, greaterThan(0));
        expect(elapsed, inInclusiveRange(15, 1000));
      });
    });

    group('isAvailable', () {
      test('is true in Chrome', () {
        expect(api.isAvailable, isTrue);
      });
    });

    group('isSecureContext', () {
      test('is true on localhost', () {
        expect(api.isSecureContext, isTrue);
      });
    });
  });

  group('WebMidiAccess of the browser', () {
    test('lists the ports with their states', () async {
      final access = await grantedAccess();
      if (access == null) return;

      for (final port in <WebMidiPortHandle>[
        ...access.inputs,
        ...access.outputs,
      ]) {
        expect(port.id, isNotEmpty);
        expect(port.state, isIn(['connected', 'disconnected']));
        expect(port.connection, isIn(['open', 'closed', 'pending']));
      }
    });

    test('reports state changes until the subscription ends', () async {
      final access = await grantedAccess();
      if (access == null) return;

      final subscription = access.stateChanges.listen((_) {});

      await expectLater(subscription.cancel(), completes);
    });
  });

  group('WebMidiBackend()', () {
    test('starts and stops with the browser API', () async {
      final backend = WebMidiBackend();
      try {
        await backend.start(_Host());
      } on MidiPermissionDenied catch (error) {
        expect(error.permission, MidiPermission.midi);
        markTestSkipped('The browser denied the MIDI permission');
        return;
      }
      final access = await api.requestAccess(sysEx: false, software: false);

      expect(
        backend.ports.map((port) => port.native['id']),
        equals([
          for (final port in access.inputs) port.id,
          for (final port in access.outputs) port.id,
        ]),
      );
      expect(
        backend.capabilities.missingPermissions,
        equals({MidiPermission.sysEx}),
      );

      await backend.stop();

      expect(backend.ports, isEmpty);
    });

    test('gets System Exclusive or reports its denial', () async {
      final backend = WebMidiBackend(sysEx: true);
      try {
        await backend.start(_Host());
      } on MidiPermissionDenied catch (error) {
        expect(error.permission, MidiPermission.sysEx);
        expect(
          backend.capabilities.missingPermissions,
          equals({MidiPermission.midi, MidiPermission.sysEx}),
        );
        return;
      }

      expect(backend.capabilities.missingPermissions, isEmpty);
      await backend.stop();
    });
  });

  // The ports of tool/macos_midi_loopback.swift echo what they get; without
  // them, these tests are skipped.
  group('WebMidiBackend() on a loopback', () {
    late _Host host;
    late WebMidiBackend backend;
    MidiPortInfo? input;
    MidiPortInfo? output;

    setUp(() async {
      host = _Host();
      backend = WebMidiBackend();
      input = null;
      output = null;
      try {
        await backend.start(host);
      } on MidiPermissionDenied {
        return;
      }
      MidiPortInfo? find(MidiDirection direction) => backend.ports
          .where((p) => p.direction == direction && p.name == loopbackName)
          .firstOrNull;
      input = find(MidiDirection.input);
      output = find(MidiDirection.output);
      if (input == null || output == null) return;
      await backend.openPort(input!.id);
      await backend.openPort(output!.id);
    });

    tearDown(() => backend.stop());

    bool hasNoLoopback() {
      if (input != null && output != null) return false;
      markTestSkipped('No "$loopbackName" ports: run the loopback tool');
      return true;
    }

    Future<List<(MidiPortId, MidiPacket)>> sendAndEcho(
      List<int> bytes, {
      required MidiTime at,
      int echoes = 1,
    }) async {
      final echo = host.packets.take(echoes).toList();
      await backend.send(
        output!.id,
        MidiBytesPacket(bytes: MidiBytes(bytes), time: at),
      );
      return echo.timeout(const Duration(seconds: 2));
    }

    test('echoes bytes sent at once, stamped on arrival', () async {
      if (hasNoLoopback()) return;
      final sentAt = host.clock.now();

      final [(port, packet)] = await sendAndEcho([
        0x90,
        0x3C,
        0x64,
      ], at: sentAt);

      expect(port, input!.id);
      expect(
        packet,
        isA<MidiBytesPacket>().having(
          (p) => p.bytes,
          'bytes',
          MidiBytes([0x90, 0x3C, 0x64]),
        ),
      );
      expect(
        packet.time.difference(sentAt).inMicroseconds,
        inInclusiveRange(-1000, 50000),
      );
    });

    test('echoes bytes scheduled for later at their due time', () async {
      if (hasNoLoopback()) return;
      final due = host.clock.now() + const Duration(milliseconds: 100);

      final [(_, packet)] = await sendAndEcho([0x80, 0x3C, 0x00], at: due);

      expect(
        packet.time.difference(due).inMicroseconds,
        inInclusiveRange(-1000, 20000),
      );
    });

    test('echoes the messages of one packet one by one', () async {
      if (hasNoLoopback()) return;

      final echoes = await sendAndEcho(
        [0xB0, 0x07, 0x64, 0xC0, 0x05, 0xF8],
        at: host.clock.now(),
        echoes: 3,
      );

      expect(
        echoes.map((echo) => (echo.$2 as MidiBytesPacket).bytes.toHex()),
        equals(['b0 07 64', 'c0 05', 'f8']),
      );
    });

    test('reports bytes the browser would refuse and sends none', () async {
      if (hasNoLoopback()) return;

      await backend.send(
        output!.id,
        MidiBytesPacket(
          bytes: MidiBytes([0x90, 0x3C, 0x64, 0x3E, 0x64]),
          time: host.clock.now(),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(host.log, isEmpty);
      expect(
        host.diagnostics.map((d) => d.kind),
        equals([MidiDiagnosticKind.invalidData]),
      );
    });

    test('cancels pending sends only where the browser has clear()', () async {
      if (hasNoLoopback()) return;

      final cancel = backend.cancelPending(output!.id);

      if (output!.capabilities.cancelPending) {
        await expectLater(cancel, completes);
      } else {
        await expectLater(cancel, throwsA(isA<MidiUnsupported>()));
      }
    });

    test('lets the adapter turn refused bytes into exceptions', () async {
      if (hasNoLoopback()) return;
      final access = await api.requestAccess(sysEx: false, software: false);
      final port = access.outputs.firstWhere((p) => p.name == loopbackName);

      for (final (bytes, names, text) in [
        ([0x3C], ['TypeError', 'Error'], 'Running status is not allowed'),
        ([0xF0, 0x7E, 0xF7], ['NotAllowedError'], 'System exclusive'),
      ]) {
        expect(
          () => port.send(Uint8List.fromList(bytes)),
          throwsA(
            isA<WebMidiDomException>()
                .having((e) => e.name, 'name', isIn(names))
                .having((e) => e.message, 'message', contains(text)),
          ),
        );
      }
    });
  });
}

// #############################################################################
/// The package clock in the browser: `performance.now()` in microseconds.
final class _BrowserClock implements MidiClock {
  const _BrowserClock();

  @override
  MidiTime now() => MidiTime((const WebMidiBrowserApi().now() * 1000).round());
}

// #############################################################################
/// Records what the backend reports.
final class _Host implements MidiBackendHost {
  @override
  final MidiClock clock = const _BrowserClock();

  final log = <(MidiPortId, MidiPacket)>[];
  final diagnostics = <MidiDiagnostic>[];
  final _packets = StreamController<(MidiPortId, MidiPacket)>.broadcast(
    sync: true,
  );

  /// The received packets as they arrive.
  Stream<(MidiPortId, MidiPacket)> get packets => _packets.stream;

  @override
  void portsChanged(List<MidiPortEvent> events) {}

  @override
  void received(MidiPortId port, MidiPacket packet) {
    log.add((port, packet));
    _packets.add((port, packet));
  }

  @override
  void diagnostic(MidiDiagnostic diagnostic) => diagnostics.add(diagnostic);
}
