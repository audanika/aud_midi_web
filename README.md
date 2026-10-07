# aud_midi_web

The browser backend of aud_midi, built on the Web MIDI API through package:web.

Part of the aud_midi family, see [aud_midi](https://github.com/audmidi/aud_midi).

## Goals

- Web MIDI inputs, outputs and hotplug
- Sysex and scheduled send
- Translation to MIDI 2.0 on top of byte ports

## State

`WebMidiBackend` (backend name `webmidi`) implements `MidiBackend` of
aud_midi_core:

- `start` calls `navigator.requestMIDIAccess({sysex, software})`. No Web
  MIDI or no secure context → `MidiUnsupported`; a refused permission →
  `MidiPermissionDenied` (`sysEx` when requested, else `midi`); any other
  failure → `MidiNativeError` plus a `nativeError` diagnostic
- Every Web MIDI port becomes a MIDI 1.0 byte port on a synthetic one-port
  device, id `webmidi:input:<MIDIPort.id>` or `webmidi:output:<MIDIPort.id>`,
  transport `unknown`; MIDI 2.0 comes from the engine's translation
- Inputs deliver `MidiBytesPacket`s with the browser's receive time on the
  package clock (`MidiClockMapper` on `performance.now()`, measured again
  every 10 s and on hotplug)
- Outputs schedule in the browser: `send(data, timestamp)` with the due
  time. Bytes the browser would refuse (running status, split or
  unpermitted SysEx, undefined status bytes, incomplete messages) and
  exceptions of the browser become diagnostics
- `cancelPending` uses `MIDIOutput.clear()` where the browser has it;
  Chrome 153 has not, so `capabilities.cancelPending` is false there
- Hotplug through `onstatechange` → `MidiPortAdded`, `MidiPortChanged`,
  `MidiPortRemoved`; an open port that disappears is closed
- No virtual ports, Bluetooth scan or network sessions: Web MIDI has none

Verified:

- The logic on the Dart VM against a fake of the browser interface, 100 %
  coverage per file: `dart test`
- In headless Chrome 153 with dart2js and dart2wasm: `dart test -P browser`
  loads the adapter, requests access with and without SysEx and starts and
  stops the backend on the real API. Headless Chrome denies permission
  prompts; `dart_test.yaml` passes `--disable-features=BlockMidiByDefault`,
  which grants MIDI without SysEx. SysEx stays denied there
- Through a CoreMIDI loopback (`tool/macos_midi_loopback.swift`): round trip
  with receive stamps within 1 ms of the send call, sends scheduled 100 ms
  ahead arrive at their due time (±0.1 ms), one packet arrives as one event
  per message, refused bytes become diagnostics. Hotplug by hand with the
  tool's delay and lifetime

## Usage notes

- Web MIDI needs a secure context: https or localhost. Elsewhere
  `navigator.requestMIDIAccess` is missing and `start` throws
  `MidiUnsupported`
- `start` makes the browser ask for permission; current Chrome versions
  ask for every access. `WebMidiBackend(sysEx: true)` asks for System
  Exclusive, a stronger permission to "control and reprogram" MIDI devices
- In an iframe, the embedding page must allow MIDI: `<iframe allow="midi">`;
  servers can set `Permissions-Policy: midi=(self)`
- Web MIDI exists on the browser's main thread only, so on the Web the
  backend runs in the page, not in a MIDI isolate
- Bluetooth devices appear only when the operating system paired them
  (macOS, Windows), as ordinary ports

| Browser | Web MIDI |
| --- | --- |
| Chrome 43+, Edge 79+, Opera 30+ | yes |
| Firefox 108+ | yes, after a site permission add-on prompt |
| Chrome Android, Samsung Internet | yes, no Bluetooth MIDI |
| Safari, every browser on iOS | no |
| Firefox Android | no |

## Installation

```bash
dart pub add aud_midi_web
```

## Code Examples

```dart
import 'package:aud_midi_core/aud_midi_core.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:aud_midi_web/aud_midi_web.dart';

Future<void> main() async {
  final backend = WebMidiBackend();
  try {
    await backend.start(PrintingHost());
  } on MidiException catch (error) {
    print(error); // e.g. the user denied the permission
    return;
  }
  for (final port in backend.ports) {
    print('${port.direction.name}: ${port.name} (${port.id})');
  }
  await backend.stop();
}

/// Prints what the backend reports; apps get this from aud_midi's engine.
final class PrintingHost implements MidiBackendHost {
  @override
  final MidiClock clock = const MidiSystemClock();

  @override
  void portsChanged(List<MidiPortEvent> events) => print(events);

  @override
  void received(MidiPortId port, MidiPacket packet) => print(packet);

  @override
  void diagnostic(MidiDiagnostic diagnostic) => print(diagnostic);
}
```

## How It Works

- `WebMidiApi`, `WebMidiAccess`, `WebMidiInputHandle` and
  `WebMidiOutputHandle` describe the browser API in pure Dart
- `lib/src/browser/web_midi_browser_api.dart` implements them with
  package:web; a conditional import (`dart.library.js_interop`) picks it in
  the browser and `WebMidiUnavailableApi` everywhere else
- `WebMidiBackend` holds all logic against these interfaces, so the Dart VM
  tests it with a fake; `WebMidiMessageValidator` checks bytes the way
  `MIDIOutput.send()` does

Tests:

```bash
dart test                        # logic, Dart VM
dart test -P browser             # adapter in Chrome, dart2js
dart test -P browser -c dart2wasm
swift tool/macos_midi_loopback.swift &   # enables the loopback tests
```

## Contributing

See [doc/guides/develop-guide.md](doc/guides/develop-guide.md).
