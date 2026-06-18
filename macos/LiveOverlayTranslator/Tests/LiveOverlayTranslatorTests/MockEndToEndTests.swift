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
    #expect(state.cards.first?.result?.translationRU == "Не могли бы вы прислать мне обновлённое предложение к пятнице?")
    #expect(state.cards.first?.result?.suggestedReplyEN == "Yes, I'll finish the revisions and send you the updated version by Friday.")
}
