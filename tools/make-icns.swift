#!/usr/bin/env swift
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("usage: make-icns.swift INPUT.iconset OUTPUT.icns\n", stderr)
    exit(2)
}

let input = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let entries = [
    ("icp4", "icon_16x16.png"),
    ("ic11", "icon_16x16@2x.png"),
    ("icp5", "icon_32x32.png"),
    ("ic12", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic13", "icon_128x128@2x.png"),
    ("ic08", "icon_256x256.png"),
    ("ic14", "icon_256x256@2x.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png")
]

func fourCC(_ value: String) -> Data {
    precondition(value.utf8.count == 4)
    return Data(value.utf8)
}

func bigEndian(_ value: Int) -> Data {
    var number = UInt32(value).bigEndian
    return withUnsafeBytes(of: &number) { Data($0) }
}

var body = Data()
for (type, filename) in entries {
    let png = try Data(contentsOf: input.appendingPathComponent(filename))
    body.append(fourCC(type))
    body.append(bigEndian(png.count + 8))
    body.append(png)
}

var result = Data()
result.append(fourCC("icns"))
result.append(bigEndian(body.count + 8))
result.append(body)
try result.write(to: output, options: .atomic)
