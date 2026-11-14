import Testing
import Foundation
@testable import FinderWheelCore

@Suite struct WheelConfigurationTests {
    private func verbs(_ entries: [WheelEntry]) -> [Slot: Verb] {
        Dictionary(uniqueKeysWithValues: entries.map { ($0.slot, $0.verb) })
    }

    // MARK: Catalog

    @Test func catalogMatchesWhatTheRouterCanRun() {
        for c in Classification.allCases {
            let kinds: [FileKind]
            switch c {
            case .pdf: kinds = [.pdf]
            case .image: kinds = [.image]
            case .video: kinds = [.video]
            case .audio: kinds = [.audio]
            case .videoAudio: kinds = [.video, .audio]
            case .pdfImage: kinds = [.pdf, .image]
            case .unsupported: kinds = []
            }
            for verb in WheelCatalog.verbs(for: c) where verb != .combine {
                for option in WheelCatalog.options(for: verb, classification: c) {
                    for kind in kinds {
                        #expect(ActionRouter.action(for: option.action, fileKind: kind) != nil, "\(c) \(option.id) on \(kind)")
                    }
                }
            }
        }
        #expect(WheelCatalog.verbs(for: .unsupported).isEmpty)
    }

    /// The wheel as it shipped before it became configurable.
    @Test func standardConfigurationReproducesTheShippedWheel() {
        struct Expected { let slot: Slot; let verb: Verb; let options: [String]; let def: String; let remembers: Bool }
        let table: [WheelFileType: [Expected]] = [
            .pdf: [
                Expected(slot: .up, verb: .markdown, options: ["markdown"], def: "markdown", remembers: false),
                Expected(slot: .upperRight, verb: .convert, options: ["png", "jpg"], def: "png", remembers: true),
                Expected(slot: .lowerRight, verb: .compress, options: ["light", "medium", "strong"], def: "medium", remembers: true),
                Expected(slot: .lowerLeft, verb: .split, options: ["split"], def: "split", remembers: false),
                Expected(slot: .upperLeft, verb: .combine, options: ["combine"], def: "combine", remembers: false),
            ],
            .image: [
                Expected(slot: .up, verb: .markdown, options: ["markdown"], def: "markdown", remembers: false),
                Expected(slot: .upperRight, verb: .convert, options: ["jpg", "png", "heic", "tiff"], def: "jpg", remembers: true),
                Expected(slot: .lowerRight, verb: .compress, options: ["light", "medium", "strong", "resize"], def: "medium", remembers: true),
                Expected(slot: .lowerLeft, verb: .cutOut, options: ["cutOut"], def: "cutOut", remembers: false),
                Expected(slot: .upperLeft, verb: .combine, options: ["combine"], def: "combine", remembers: false),
            ],
            .video: [
                Expected(slot: .up, verb: .markdown, options: ["markdown"], def: "markdown", remembers: false),
                Expected(slot: .upperRight, verb: .convert, options: ["mp4", "gif", "m4a"], def: "mp4", remembers: true),
                Expected(slot: .lowerRight, verb: .compress, options: ["light", "medium", "strong"], def: "medium", remembers: true),
            ],
            .audio: [
                Expected(slot: .up, verb: .markdown, options: ["markdown"], def: "markdown", remembers: false),
                Expected(slot: .upperRight, verb: .convert, options: ["m4a"], def: "m4a", remembers: false),
                Expected(slot: .lowerRight, verb: .compress, options: ["light", "medium", "strong"], def: "medium", remembers: true),
            ],
        ]
        for type in WheelFileType.allCases {
            let entries = WheelLayout.entries(for: type.classification, fileCount: 2)
            let expected = table[type]!
            #expect(entries.count == expected.count, "\(type)")
            for e in expected {
                let entry = entries.first { $0.slot == e.slot }
                #expect(entry?.verb == e.verb, "\(type) \(e.slot)")
                #expect(entry?.options.map(\.id) == e.options, "\(type) \(e.verb)")
                #expect(entry?.defaultOptionID == e.def, "\(type) \(e.verb)")
                #expect(entry?.remembersLastUsed == e.remembers, "\(type) \(e.verb)")
            }
        }
    }

    // MARK: Editing

    @Test func assigningAnActionThatIsElsewhereSwapsTheTwoDirections() {
        var config = WheelConfiguration.standard(for: .image)
        config.assign(.markdown, to: .down, type: .image)
        #expect(config[.down]?.verb == .markdown)
        #expect(config[.up] == nil)

        config.assign(.convert, to: .down, type: .image)
        #expect(config[.down]?.verb == .convert)
        #expect(config[.upperRight]?.verb == .markdown)
    }

    @Test func movingAnActionKeepsItsOptions() {
        var config = WheelConfiguration.standard(for: .image)
        config.setOption("tiff", shown: false, at: .upperRight)
        config.assign(.convert, to: .lowerLeft, type: .image)
        #expect(config[.lowerLeft]?.optionIDs == ["jpg", "png", "heic"])
        #expect(config[.upperRight]?.verb == .cutOut)
    }

    @Test func assigningNilEmptiesTheDirection() {
        var config = WheelConfiguration.standard(for: .pdf)
        config.assign(nil, to: .lowerLeft, type: .pdf)
        #expect(config[.lowerLeft] == nil)
        #expect(!WheelLayout.entries(for: .pdf, fileCount: 2, configurations: WheelConfigurations([.pdf: config]))
            .contains { $0.verb == .split })
    }

    @Test func swappingEmptyAndFilledDirections() {
        var config = WheelConfiguration.standard(for: .video)
        config.swap(.upperRight, .down)
        #expect(config[.upperRight] == nil)
        #expect(config[.down]?.verb == .convert)
    }

    @Test func hidingOptionsNeverEmptiesTheRingAndMovesTheDefault() {
        var config = WheelConfiguration.standard(for: .pdf)
        config.setOption("png", shown: false, at: .upperRight)
        #expect(config[.upperRight]?.optionIDs == ["jpg"])
        #expect(config[.upperRight]?.defaultOptionID == "jpg")
        config.setOption("jpg", shown: false, at: .upperRight)
        #expect(config[.upperRight]?.optionIDs == ["jpg"])
        config.setOption("png", shown: true, at: .upperRight)
        #expect(config[.upperRight]?.optionIDs == ["jpg", "png"])
    }

    @Test func reorderingAndDefault() {
        var config = WheelConfiguration.standard(for: .image)
        config.moveOption("tiff", onto: "jpg", at: .upperRight)
        #expect(config[.upperRight]?.optionIDs == ["tiff", "jpg", "png", "heic"])
        config.moveOption("tiff", onto: "heic", at: .upperRight)
        #expect(config[.upperRight]?.optionIDs == ["jpg", "png", "heic", "tiff"])
        config.moveOption("png", onto: "heic", at: .upperRight)
        #expect(config[.upperRight]?.optionIDs == ["jpg", "heic", "png", "tiff"])
        config.moveOption("png", onto: "bmp", at: .upperRight)
        #expect(config[.upperRight]?.optionIDs == ["jpg", "heic", "png", "tiff"])
        config.moveOption("png", onto: "heic", at: .upperRight)
        config.setDefault("heic", at: .upperRight)
        #expect(config[.upperRight]?.defaultOptionID == "heic")
        config.setDefault("gif", at: .upperRight)
        #expect(config[.upperRight]?.defaultOptionID == "heic")
    }

    @Test func customConfigurationDrivesTheWheel() {
        var config = WheelConfiguration.standard(for: .image)
        config.assign(.compress, to: .up, type: .image)
        config.moveOption("resize", onto: "light", at: .up)
        config.setOption("light", shown: false, at: .up)
        config.setDefault("resize", at: .up)
        config.setRemembersLastUsed(false, at: .up)
        let entries = WheelLayout.entries(for: .image, fileCount: 1, configurations: WheelConfigurations([.image: config]))
        let up = entries.first { $0.slot == .up }
        #expect(up?.verb == .compress)
        #expect(up?.options.map(\.id) == ["resize", "medium", "strong"])
        #expect(up?.defaultOptionID == "resize")
        #expect(up?.remembersLastUsed == false)
        #expect(entries.first { $0.slot == .lowerRight }?.verb == .markdown)
    }

    @Test func singleOptionEntriesNeverRemember() {
        var config = WheelConfiguration.standard(for: .pdf)
        config.setOption("png", shown: false, at: .upperRight)
        let entry = WheelLayout.entries(for: .pdf, fileCount: 1, configurations: WheelConfigurations([.pdf: config]))
            .first { $0.verb == .convert }
        #expect(entry?.options.map(\.id) == ["jpg"])
        #expect(entry?.remembersLastUsed == false)
    }

    @Test func assigningAnUnsupportedActionDoesNothing() {
        var config = WheelConfiguration.standard(for: .video)
        config.assign(.cutOut, to: .down, type: .video)
        #expect(config == .standard(for: .video))
    }

    // MARK: Sanitizing

    @Test func decodingKeepsReadableDirectionsAndPadsShortData() throws {
        let json = """
        {"slots":[{"verb":"markdown","optionIDs":["markdown"],"defaultOptionID":"markdown","remembersLastUsed":false},
                  {"verb":"teleport","optionIDs":["x"],"defaultOptionID":"x","remembersLastUsed":false},
                  null,
                  {"verb":"compress","optionIDs":["strong"],"defaultOptionID":"strong","remembersLastUsed":true}]}
        """
        var config = try JSONDecoder().decode(WheelConfiguration.self, from: Data(json.utf8))
        #expect(config[.up]?.verb == .markdown)
        #expect(config[.upperRight] == nil)
        #expect(config[.down]?.optionIDs == ["strong"])
        config[.upperLeft] = .standard(.combine, for: .pdf)
        #expect(config[.upperLeft]?.verb == .combine)
        let roundTrip = try JSONDecoder().decode(WheelConfiguration.self, from: JSONEncoder().encode(config))
        #expect(roundTrip == config)
    }

    @Test func sanitizingRepairsStoredConfigurations() {
        let broken = WheelConfiguration([
            .up: SlotConfiguration(verb: .cutOut, optionIDs: ["cutOut"], defaultOptionID: "cutOut", remembersLastUsed: false),
            .upperRight: SlotConfiguration(verb: .convert, optionIDs: ["bmp", "jpg", "jpg"], defaultOptionID: "png", remembersLastUsed: true),
            .lowerRight: SlotConfiguration(verb: .compress, optionIDs: [], defaultOptionID: "x", remembersLastUsed: true),
            .down: SlotConfiguration(verb: .convert, optionIDs: ["png"], defaultOptionID: "png", remembersLastUsed: true),
        ])
        let fixed = broken.sanitized(for: .pdf)
        #expect(fixed[.up] == nil)
        #expect(fixed[.upperRight]?.optionIDs == ["jpg"])
        #expect(fixed[.upperRight]?.defaultOptionID == "jpg")
        #expect(fixed[.lowerRight]?.optionIDs == ["light", "medium", "strong"])
        #expect(fixed[.lowerRight]?.defaultOptionID == "medium")
        #expect(fixed[.down] == nil)
    }

    // MARK: Mixed selections

    @Test func mixesFollowTheFirstTypesPlacement() {
        var pdf = WheelConfiguration.standard(for: .pdf)
        pdf.assign(.combine, to: .down, type: .pdf)
        var image = WheelConfiguration.standard(for: .image)
        image.assign(.compress, to: .up, type: .image)
        let entries = WheelLayout.entries(for: .pdfImage, fileCount: 2,
                                          configurations: WheelConfigurations([.pdf: pdf, .image: image]))
        #expect(verbs(entries) == [.up: .markdown, .lowerRight: .compress, .down: .combine])
    }

    @Test func mixLeavesOutActionsRemovedFromEitherWheel() {
        // Removed from the PDF wheel only: a mix must not bring it back from the image wheel.
        var pdf = WheelConfiguration.standard(for: .pdf)
        pdf.assign(nil, to: .up, type: .pdf)
        var entries = WheelLayout.entries(for: .pdfImage, fileCount: 2, configurations: WheelConfigurations([.pdf: pdf]))
        #expect(verbs(entries) == [.lowerRight: .compress, .upperLeft: .combine])

        var audio = WheelConfiguration.standard(for: .audio)
        audio.assign(nil, to: .upperRight, type: .audio)
        entries = WheelLayout.entries(for: .videoAudio, fileCount: 2, configurations: WheelConfigurations([.audio: audio]))
        #expect(verbs(entries) == [.up: .markdown, .lowerRight: .compress])
        #expect(entries.allSatisfy { !$0.remembersLastUsed })
    }

    @Test func mixShowsOnlyTheOptionsThatApplyToEveryFile() {
        let entries = WheelLayout.entries(for: .videoAudio, fileCount: 2)
        #expect(entries.first { $0.verb == .convert }?.options.map(\.id) == ["m4a"])
    }

    @Test func mixUsesTheConfiguredOptionOrderAndDefault() {
        var pdf = WheelConfiguration.standard(for: .pdf)
        pdf.moveOption("strong", onto: "light", at: .lowerRight)
        pdf.setDefault("strong", at: .lowerRight)
        let compress = WheelLayout.entries(for: .pdfImage, fileCount: 2, configurations: WheelConfigurations([.pdf: pdf]))
            .first { $0.verb == .compress }
        #expect(compress?.options.map(\.id) == ["strong", "light", "medium"])
        #expect(compress?.defaultOptionID == "strong")
    }
}
