#!/usr/bin/env swift
import AppKit
import Foundation

guard CommandLine.arguments.count == 4 else {
    fputs("usage: compose-qa.swift source.png implementation.png output.png\n", stderr)
    exit(2)
}

let paths = CommandLine.arguments.dropFirst().map { URL(fileURLWithPath: $0) }
guard let source = NSImage(contentsOf: paths[0]), let implementation = NSImage(contentsOf: paths[1]) else {
    fputs("unable to load input image\n", stderr)
    exit(3)
}

let panelSize = NSSize(width: 648, height: 480)
let canvas = NSImage(size: NSSize(width: 1296, height: 480))
canvas.lockFocus()
NSColor.white.setFill()
NSRect(origin: .zero, size: canvas.size).fill()
source.draw(in: NSRect(x: 0, y: 0, width: panelSize.width, height: panelSize.height))
implementation.draw(in: NSRect(x: 648, y: 0, width: panelSize.width, height: panelSize.height))
canvas.unlockFocus()

guard let tiff = canvas.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("unable to encode output image\n", stderr)
    exit(4)
}
try png.write(to: paths[2])
