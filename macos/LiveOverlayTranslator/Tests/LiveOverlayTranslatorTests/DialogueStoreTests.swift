import Testing
@testable import LiveOverlayTranslatorCore

@Test
func suggestedRepliesAreExcludedUntilMarkedUsed() {
    var store = DialogueStore(maxTurns: 10)
    store.addFinalizedSpeech(speaker: .remote, text: "Can you send it?", sequence: 1)
    store.addSuggestedReply(ru: "Yes, I will send it.", en: "Yes, I will send it.", sequence: 2)

    #expect(store.context() == [
        DialogueTurn(speaker: .remote, text: "Can you send it?")
    ])

    store.markSuggestedReplyUsed(text: "Yes, I will send it.", sequence: 3)

    #expect(store.context() == [
        DialogueTurn(speaker: .remote, text: "Can you send it?"),
        DialogueTurn(speaker: .local, text: "Yes, I will send it.")
    ])
}
