import Testing
import Foundation
@testable import FinderWheelCore

@Suite struct ReorderTests {
    private func urls(_ names: [String]) -> [URL] { names.map { URL(fileURLWithPath: "/tmp/\($0)") } }

    @Test func naturalOrderSortsNumbersNumerically() {
        let sorted = Reorder.naturalOrder(urls(["10 Appendix.pdf", "2 Intro.pdf", "1 Cover.pdf", "b.pdf", "A.pdf"]))
        #expect(sorted.map(\.lastPathComponent) == ["1 Cover.pdf", "2 Intro.pdf", "10 Appendix.pdf", "A.pdf", "b.pdf"])
    }

    @Test func moveForwardPlacesAfterTarget() {
        #expect(Reorder.move("a", onto: "c", in: ["a", "b", "c", "d"]) == ["b", "c", "a", "d"])
    }

    @Test func moveBackwardPlacesBeforeTarget() {
        #expect(Reorder.move("d", onto: "b", in: ["a", "b", "c", "d"]) == ["a", "d", "b", "c"])
    }

    @Test func moveOntoItselfOrUnknownIsANoOp() {
        #expect(Reorder.move("b", onto: "b", in: ["a", "b", "c"]) == ["a", "b", "c"])
        #expect(Reorder.move("x", onto: "b", in: ["a", "b", "c"]) == ["a", "b", "c"])
        #expect(Reorder.move("a", onto: "x", in: ["a", "b", "c"]) == ["a", "b", "c"])
    }
}
