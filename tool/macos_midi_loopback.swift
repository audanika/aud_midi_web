// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

// A CoreMIDI loopback for the browser tests on macOS: a virtual destination
// that echoes everything it receives to a virtual source of the same name,
// stamped with the time of arrival. Chrome lists the pair as an output and
// an input named "aud_midi_web loopback"; the loopback tests in
// test/browser use them.
//
//   swift tool/macos_midi_loopback.swift [name] [delay] [lifetime]
//
// - name      the port name, "aud_midi_web loopback" by default
// - delay     seconds until the ports appear, 0 by default
// - lifetime  seconds until the ports disappear and the tool ends; it runs
//             until Ctrl-C without
//
// Delay and lifetime let the ports appear and disappear while a page runs,
// e.g. to watch hotplug.
import CoreMIDI
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)
let arguments = Array(CommandLine.arguments.dropFirst())
let name = arguments.first ?? "aud_midi_web loopback"
let delay = arguments.count > 1 ? Double(arguments[1]) ?? 0 : 0
let lifetime = arguments.count > 2 ? Double(arguments[2]) : nil

func check(_ status: OSStatus, _ call: String) {
  if status != noErr {
    print("\(call) failed: \(status)")
    exit(1)
  }
}

var client = MIDIClientRef()
check(
  MIDIClientCreateWithBlock(name as CFString, &client, nil),
  "MIDIClientCreate")

let bufferSize = 65536
let buffer = UnsafeMutableRawPointer.allocate(
  byteCount: bufferSize, alignment: 16)
var source = MIDIEndpointRef()
var destination = MIDIEndpointRef()

/// Creates the source and the destination that echoes to it.
func create() {
  check(
    MIDISourceCreateWithProtocol(client, name as CFString, ._1_0, &source),
    "MIDISourceCreate")
  check(
    MIDIDestinationCreateWithProtocol(
      client, name as CFString, ._1_0, &destination
    ) { list, _ in
      let now = mach_absolute_time()
      let echo = buffer.bindMemory(to: MIDIEventList.self, capacity: 1)
      var current = MIDIEventListInit(echo, ._1_0)
      for packet in list.unsafeSequence() {
        let words = UnsafeRawPointer(packet)
          .advanced(by: MemoryLayout<MIDIEventPacket>.offset(of: \.words)!)
          .assumingMemoryBound(to: UInt32.self)
        current = MIDIEventListAdd(
          echo, bufferSize, current, now, Int(packet.pointee.wordCount), words)
      }
      MIDIReceivedEventList(source, echo)
    }, "MIDIDestinationCreate")
  print("created '\(name)'")
}

/// Removes the source and the destination.
func remove() {
  MIDIEndpointDispose(destination)
  MIDIEndpointDispose(source)
  print("removed '\(name)'")
}

DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
  create()
  guard let lifetime else { return }
  DispatchQueue.main.asyncAfter(deadline: .now() + lifetime) {
    remove()
    exit(0)
  }
}
dispatchMain()
