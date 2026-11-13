import Testing
@testable import FinderWheelCore

@Suite struct ClassificationTests {
    @Test func packageBuilds() {
        #expect(FileKind.pdf != FileKind.image)
    }
}
