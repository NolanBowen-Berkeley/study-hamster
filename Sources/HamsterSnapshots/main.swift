import AppKit
import Foundation
import HamsterUI

// HamsterSnapshots — renders the hamster to PNG for visual review, verifies the animator, writes the icon.
//
//   HamsterSnapshots [outputDir]              poses, stage composites and animation strips (default ./snapshots)
//   HamsterSnapshots --verify-animator        samples every mode switch at 240 Hz; exit 1 on pops/NaN/no settle
//   HamsterSnapshots --icon <dir.iconset>     writes the macOS app iconset

let arguments = Array(CommandLine.arguments.dropFirst())

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("HamsterSnapshots: \(message)\n".utf8))
    exit(1)
}

if arguments.first == "--verify-animator" {
    exit(AnimatorVerifier.run() ? 0 : 1)
}

MainActor.assumeIsolated {
    do {
        if arguments.first == "--icon" {
            guard arguments.count >= 2 else { fail("--icon needs an output folder, e.g. build/AppIcon.iconset") }
            let dir = URL(fileURLWithPath: arguments[1], isDirectory: true)
            let files = try IconSet.write(to: dir)
            print("wrote \(files.count) icon images to \(dir.path)")
            return
        }
        if let flag = arguments.first, flag.hasPrefix("--") {
            fail("unknown option \(flag) (use [outputDir], --verify-animator or --icon <dir.iconset>)")
        }
        let dir = URL(fileURLWithPath: arguments.first ?? "snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var files: [URL] = []
        files += try Scenes.renderPoses(to: dir)
        files += try Scenes.renderComposites(to: dir)
        files += try Scenes.renderStrips(to: dir)
        print("wrote \(files.count) snapshots (+ single poses in poses/) to \(dir.path)")
    } catch {
        fail("\(error)")
    }
}
