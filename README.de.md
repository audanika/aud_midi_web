# aud_midi_web

Das Browser-Backend von aud_midi, gebaut auf der Web-MIDI-API über package:web.

Teil der aud_midi-Familie, siehe [aud_midi](https://github.com/audmidi/aud_midi).

## Ziele

- Web-MIDI-Ein- und Ausgänge und Hotplug
- Sysex und zeitgesteuertes Senden
- Übersetzung nach MIDI 2.0 auf Byte-Ports

## Stand

`WebMidiBackend` (Backend-Name `webmidi`) implementiert `MidiBackend` aus
aud_midi_core:

- `start` ruft `navigator.requestMIDIAccess({sysex, software})` auf. Kein
  Web MIDI oder kein sicherer Kontext → `MidiUnsupported`; verweigerte
  Berechtigung → `MidiPermissionDenied` (`sysEx`, wenn angefragt, sonst
  `midi`); jeder andere Fehler → `MidiNativeError` plus eine
  `nativeError`-Diagnose
- Jeder Web-MIDI-Port wird ein MIDI-1.0-Byte-Port auf einem synthetischen
  Gerät mit einem Port, Id `webmidi:input:<MIDIPort.id>` oder
  `webmidi:output:<MIDIPort.id>`, Transport `unknown`; MIDI 2.0 kommt aus der
  Übersetzung der Engine
- Eingänge liefern `MidiBytesPacket`s mit der Empfangszeit des Browsers auf
  der Paket-Uhr (`MidiClockMapper` auf `performance.now()`, alle 10 s und
  bei Hotplug neu gemessen)
- Ausgänge planen im Browser: `send(data, timestamp)` mit der
  Fälligkeitszeit. Bytes, die der Browser ablehnen würde (Running Status,
  geteiltes oder nicht erlaubtes SysEx, undefinierte Statusbytes,
  unvollständige Nachrichten), und Ausnahmen des Browsers werden zu
  Diagnosen
- `cancelPending` nutzt `MIDIOutput.clear()`, wo der Browser es hat;
  Chrome 153 hat es nicht, dort ist `capabilities.cancelPending` false
- Hotplug über `onstatechange` → `MidiPortAdded`, `MidiPortChanged`,
  `MidiPortRemoved`; ein offener Port, der verschwindet, wird geschlossen
- Keine virtuellen Ports, kein Bluetooth-Scan, keine Netzwerk-Sessions: Web
  MIDI hat nichts davon

Geprüft:

- Die Logik auf der Dart-VM gegen eine Attrappe der Browser-Schnittstelle,
  100 % Abdeckung pro Datei: `dart test`
- Im Headless-Chrome 153 mit dart2js und dart2wasm: `dart test -P browser`
  lädt den Adapter, fragt Zugriff mit und ohne SysEx an und startet und
  stoppt das Backend auf der echten API. Headless-Chrome verweigert
  Berechtigungsabfragen; `dart_test.yaml` übergibt
  `--disable-features=BlockMidiByDefault`, das MIDI ohne SysEx erlaubt.
  SysEx bleibt dort verweigert
- Über einen CoreMIDI-Loopback (`tool/macos_midi_loopback.swift`):
  Rundweg mit Empfangsstempeln innerhalb 1 ms nach dem Senden, 100 ms im
  Voraus geplante Nachrichten kommen zur Fälligkeit an (±0,1 ms), ein Paket
  kommt als ein Ereignis pro Nachricht an, abgelehnte Bytes werden zu
  Diagnosen. Hotplug von Hand mit Verzögerung und Lebensdauer des Tools

## Hinweise zur Nutzung

- Web MIDI braucht einen sicheren Kontext: https oder localhost. Sonst fehlt
  `navigator.requestMIDIAccess` und `start` wirft `MidiUnsupported`
- `start` lässt den Browser um Erlaubnis fragen; aktuelle Chrome-Versionen
  fragen bei jedem Zugriff. `WebMidiBackend(sysEx: true)` fragt nach System
  Exclusive, einer stärkeren Berechtigung, MIDI-Geräte zu „steuern und neu
  zu programmieren“
- In einem iframe muss die einbettende Seite MIDI erlauben:
  `<iframe allow="midi">`; Server können `Permissions-Policy: midi=(self)`
  setzen
- Web MIDI gibt es nur im Haupt-Thread des Browsers, im Web läuft das
  Backend daher in der Seite, nicht in einem MIDI-Isolate
- Bluetooth-Geräte erscheinen nur, wenn das Betriebssystem sie gekoppelt
  hat (macOS, Windows), als gewöhnliche Ports

| Browser | Web MIDI |
| --- | --- |
| Chrome 43+, Edge 79+, Opera 30+ | ja |
| Firefox 108+ | ja, nach Abfrage eines Site-Permission-Add-ons |
| Chrome Android, Samsung Internet | ja, ohne Bluetooth-MIDI |
| Safari, alle Browser unter iOS | nein |
| Firefox Android | nein |

## Installation

```bash
dart pub add aud_midi_web
```

## Code-Beispiele

```dart
import 'package:aud_midi_core/aud_midi_core.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:aud_midi_web/aud_midi_web.dart';

Future<void> main() async {
  final backend = WebMidiBackend();
  try {
    await backend.start(PrintingHost());
  } on MidiException catch (error) {
    print(error); // z. B. hat der Nutzer die Berechtigung verweigert
    return;
  }
  for (final port in backend.ports) {
    print('${port.direction.name}: ${port.name} (${port.id})');
  }
  await backend.stop();
}

/// Gibt aus, was das Backend meldet; Apps bekommen das von der Engine von
/// aud_midi.
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

## Funktionsweise

- `WebMidiApi`, `WebMidiAccess`, `WebMidiInputHandle` und
  `WebMidiOutputHandle` beschreiben die Browser-API in reinem Dart
- `lib/src/browser/web_midi_browser_api.dart` implementiert sie mit
  package:web; ein bedingter Import (`dart.library.js_interop`) wählt ihn
  im Browser, überall sonst `WebMidiUnavailableApi`
- `WebMidiBackend` enthält die ganze Logik gegen diese Schnittstellen, die
  Dart-VM testet sie daher mit einer Attrappe; `WebMidiMessageValidator`
  prüft Bytes so wie `MIDIOutput.send()`

Tests:

```bash
dart test                        # Logik, Dart-VM
dart test -P browser             # Adapter in Chrome, dart2js
dart test -P browser -c dart2wasm
swift tool/macos_midi_loopback.swift &   # schaltet die Loopback-Tests frei
```

## Mitwirken

Siehe [doc/guides/develop-guide.md](doc/guides/develop-guide.md).
