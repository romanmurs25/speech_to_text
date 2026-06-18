import Testing
@testable import LiveOverlayTranslatorCore

@MainActor
@Test
func mockTranscriptCompletionUpdatesOverlayState() async {
    let state = OverlayState()
    let source = MockOverlayEventSource()

    for await message in source.events() {
        state.apply(message)
    }

    #expect(state.cards.count == 1)
    #expect(state.cards.first?.originalTranscript == "Could you send me the revised proposal by Friday?")
    #expect(state.cards.first?.result?.suggestedReplyEN == "Yes, I will follow up on that.")
}
