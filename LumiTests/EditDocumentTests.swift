import CoreImage
import Foundation
import Testing
@testable import Lumi

struct EditDocumentTests {
    @Test func emptyDocumentHasZeroExposure() {
        #expect(EditDocument().exposure == 0)
        #expect(EditDocument().operations.isEmpty)
    }

    @Test func settingExposureReplacesNotStacks() {
        var d = EditDocument()
        d.exposure = 1; d.exposure = 0.5
        #expect(d.operations == [.exposure(0.5)])
        #expect(d.exposure == 0.5)
    }

    @Test func zeroExposureRemovesOperation() {
        var d = EditDocument()
        d.exposure = 1; d.exposure = 0
        #expect(d.operations.isEmpty)
    }

    @Test func codableRoundTrip() throws {
        var d = EditDocument(); d.exposure = -0.75
        #expect(try JSONDecoder().decode(EditDocument.self, from: JSONEncoder().encode(d)) == d)
    }

    @Test func decodeRejectsUnknownOperation() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(EditDocument.self, from: Data(#"{"operations":[{"sepia":{}}]}"#.utf8))
        }
    }

    @Test func rendererDocumentMatchesDirectExposure() {
        let img = RendererTests.solid(0.3)
        var d = EditDocument(); d.exposure = 1
        #expect(RendererTests.pixel(Renderer.render(img, document: d)) == RendererTests.pixel(Renderer.render(img, exposure: 1)))
    }

    @Test func rendererEmptyDocumentIsIdentity() {
        let img = RendererTests.solid(0.3)
        #expect(RendererTests.pixel(Renderer.render(img, document: EditDocument())) == RendererTests.pixel(img))
    }

    @Test func renderIsDeterministicForDocument() {
        let img = RendererTests.solid(0.4)
        var d = EditDocument(); d.exposure = 0.6
        #expect(RendererTests.pixel(Renderer.render(img, document: d)) == RendererTests.pixel(Renderer.render(img, document: d)))
    }
}
