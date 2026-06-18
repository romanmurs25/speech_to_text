import Testing
@testable import LiveOverlayTranslatorCore

@Test
func deltasAreProvisionalAndCompletedTranscriptReplacesThem() {
    var assembler = TranscriptAssembler()
    assembler.apply(delta: TranscriptDelta(
        clientUtteranceID: "client-1",
        openAIItemID: "item-1",
        sequence: 1,
        source: .systemAudio,
        speaker: .remote,
        delta: "Could you sen"
    ))

    #expect(assembler.provisionalText(for: "client-1") == "Could you sen")

    assembler.apply(completed: TranscriptCompleted(
        clientUtteranceID: "client-1",
        openAIItemID: "item-1",
        sequence: 1,
        source: .systemAudio,
        speaker: .remote,
        transcript: "Could you send it?"
    ))

    #expect(assembler.provisionalText(for: "client-1") == nil)
    #expect(assembler.completedText(for: "client-1") == "Could you send it?")
}
