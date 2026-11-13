import Testing
import Foundation
@testable import FinderWheelCore

final class Box: @unchecked Sendable { var url: URL? }

@Suite struct OutputNamerTests {
    @Test func suffixAndExtension() {
        let tmp = TempFolder()
        let input = tmp.touch("report.pdf")
        #expect(OutputNamer.fileURL(for: input, suffix: "compressed", ext: "pdf").lastPathComponent == "report-compressed.pdf")
        #expect(OutputNamer.fileURL(for: input, suffix: nil, ext: "md").lastPathComponent == "report.md")
        #expect(OutputNamer.fileURL(for: input, suffix: nil, ext: "md").deletingLastPathComponent().path == tmp.url.path)
    }

    @Test func collisionsGetANumber() {
        let tmp = TempFolder()
        let input = tmp.touch("photo.heic")
        tmp.touch("photo.jpg")
        #expect(OutputNamer.fileURL(for: input, suffix: nil, ext: "jpg").lastPathComponent == "photo-2.jpg")
        tmp.touch("photo-2.jpg")
        #expect(OutputNamer.fileURL(for: input, suffix: nil, ext: "jpg").lastPathComponent == "photo-3.jpg")
    }

    @Test func namesWithDotsKeepTheirStem() {
        let tmp = TempFolder()
        let input = tmp.touch("scan.v2.final.pdf")
        #expect(OutputNamer.fileURL(for: input, suffix: "merged", ext: "pdf").lastPathComponent == "scan.v2.final-merged.pdf")
    }

    @Test func folders() throws {
        let tmp = TempFolder()
        let input = tmp.touch("report.pdf")
        #expect(OutputNamer.folderURL(for: input, suffix: "pages").lastPathComponent == "report-pages")
        try FileManager.default.createDirectory(at: tmp.file("report-pages"), withIntermediateDirectories: false)
        #expect(OutputNamer.folderURL(for: input, suffix: "pages").lastPathComponent == "report-pages-2")
    }

    @Test func pageFileNames() {
        #expect(OutputNamer.pageFileName(base: "report", index: 0, count: 5, ext: "pdf") == "report-p01.pdf")
        #expect(OutputNamer.pageFileName(base: "report", index: 11, count: 12, ext: "png") == "report-p12.png")
        #expect(OutputNamer.pageFileName(base: "report", index: 0, count: 250, ext: "png") == "report-p001.png")
    }

    @Test func atomicWriteMovesIntoPlace() throws {
        let tmp = TempFolder()
        let final = tmp.file("out.txt")
        try AtomicOutput.write(to: final) { temp in
            #expect(temp.lastPathComponent == "out.txt")
            #expect(temp.path != final.path)
            try Data("hello".utf8).write(to: temp)
        }
        #expect(try String(contentsOf: final, encoding: .utf8) == "hello")
    }

    @Test func atomicWriteLeavesNothingOnFailure() {
        let tmp = TempFolder()
        let final = tmp.file("out.txt")
        struct Boom: Error {}
        let box = Box()
        #expect(throws: Boom.self) {
            try AtomicOutput.write(to: final) { temp in
                box.url = temp
                try Data("partial".utf8).write(to: temp)
                throw Boom()
            }
        }
        #expect(!FileManager.default.fileExists(atPath: final.path))
        #expect(!FileManager.default.fileExists(atPath: box.url!.deletingLastPathComponent().path))
    }

    @Test func atomicWriteNeverOverwrites() throws {
        let tmp = TempFolder()
        let final = tmp.touch("out.txt")
        #expect(throws: (any Error).self) {
            try AtomicOutput.write(to: final) { temp in try Data("new".utf8).write(to: temp) }
        }
        #expect(try String(contentsOf: final, encoding: .utf8) == "x")
    }

    // On a single-volume machine this cannot distinguish the old behaviour; it guards against regressions only.
    @Test func atomicTempFolderIsOnTheDestinationVolume() throws {
        let tmp = TempFolder()
        let final = tmp.file("out.txt")
        try AtomicOutput.write(to: final) { temp in
            let tempVolume = try temp.deletingLastPathComponent().resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
            let destVolume = try tmp.url.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
            #expect(tempVolume?.isEqual(destVolume) == true)
            try Data("hi".utf8).write(to: temp)
        }
    }

    @Test func asyncWriteCancelledLeavesNothing() async {
        let tmp = TempFolder()
        let final = tmp.file("out.txt")
        let box = Box()
        let task = Task {
            try await AtomicOutput.write(to: final) { temp in
                box.url = temp
                try Data("partial".utf8).write(to: temp)
                try await Task.sleep(for: .seconds(30))
            }
        }
        try? await Task.sleep(for: .milliseconds(200))
        task.cancel()
        _ = await task.result
        #expect(!FileManager.default.fileExists(atPath: final.path))
        #expect(!FileManager.default.fileExists(atPath: box.url!.deletingLastPathComponent().path))
    }
}
