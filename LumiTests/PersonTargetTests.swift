import Foundation
import CoreGraphics
import Testing
@testable import Lumi

struct PersonTargetTests {
    static func face(_ x: CGFloat) -> FaceInfo { FaceInfo(box: CGRect(x: x, y: 0.4, width: 0.2, height: 0.2), landmarks: [:]) }

    @Test func peopleAreNumberedLeftToRight() {
        let s = PersonSelection(faces: [Self.face(0.7), Self.face(0.1), Self.face(0.4)])
        #expect(s.people.map(\.name) == ["Person 1", "Person 2", "Person 3"])
        #expect(s.people.map(\.faceBox.minX) == [0.1, 0.4, 0.7])
    }

    @Test func noFacesMeansNoPeople() {
        var s = PersonSelection(faces: [])
        s.tap(CGPoint(x: 0.5, y: 0.5)); s.selectAll()
        #expect(s.people.isEmpty && s.selectedPeople.isEmpty)
    }

    @Test func tapSelectsAndTapAgainDeselects() {
        var s = PersonSelection(faces: [Self.face(0.1), Self.face(0.6)])
        s.tap(CGPoint(x: 0.15, y: 0.5))
        #expect(s.selectedPeople.map(\.id) == [0])
        s.tap(CGPoint(x: 0.15, y: 0.5))
        #expect(s.selectedPeople.isEmpty)
    }

    @Test func tapOutsideAnyFaceDoesNothing() {
        var s = PersonSelection(faces: [Self.face(0.1)])
        s.tap(CGPoint(x: 0.9, y: 0.9))
        #expect(s.selected.isEmpty)
    }

    @Test func multiSelectAndClear() {
        var s = PersonSelection(faces: [Self.face(0.1), Self.face(0.6)])
        s.tap(CGPoint(x: 0.15, y: 0.5)); s.tap(CGPoint(x: 0.65, y: 0.5))
        #expect(s.selectedPeople.count == 2)
        s.clear(); #expect(s.selectedPeople.isEmpty)
        s.selectAll(); #expect(s.selectedPeople.count == 2)
    }

    @Test func toggleUnknownIdIgnored() {
        var s = PersonSelection(faces: [Self.face(0.1)])
        s.toggle(42)
        #expect(s.selected.isEmpty)
    }

    @Test func renameWorksAndRejectsBlank() {
        var s = PersonSelection(faces: [Self.face(0.1)])
        s.rename(0, to: "Mia"); #expect(s.people[0].name == "Mia")
        s.rename(0, to: "  "); #expect(s.people[0].name == "Mia")
        s.rename(9, to: "X"); #expect(s.people.count == 1)
    }

    @Test func targetIsCodable() throws {
        let t = PersonTarget(id: 1, name: "A", faceBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
        let back = try JSONDecoder().decode(PersonTarget.self, from: JSONEncoder().encode(t))
        #expect(back == t)
    }
}
