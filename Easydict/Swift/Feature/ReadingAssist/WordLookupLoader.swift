//
//  WordLookupLoader.swift
//  Easydict
//
//  Created by chenyinuo on 2026/10/21.
//  Copyright © 2026 izual. All rights reserved.
//

import CoreServices
import Defaults
import Foundation

// MARK: - WordLookupLoader

/// Loads what the dictionary card shows: pronunciation and senses from a free dictionary,
/// and the word's meaning in its sentence from the user's AI service.
enum WordLookupLoader {
    // MARK: Internal

    struct Entry {
        var phonetics: [WordLookupModel.Phonetic] = []
        var senses: [WordLookupModel.Sense] = []
    }

    /// Senses from Youdao's free web dictionary, falling back to the offline system dictionary.
    @MainActor
    static func dictionaryEntry(for word: String) async -> Entry {
        if let entry = try? await youdaoEntry(for: word), !entry.senses.isEmpty {
            return entry
        }
        logInfo("Youdao has no entry for \(word), use the system dictionary")
        return systemDictionaryEntry(for: word) ?? Entry()
    }

    /// The word's meaning as used in `sentence`, from the text replacement service when it is
    /// an AI service, otherwise from the built-in AI. Streams the accumulated answer.
    @MainActor
    static func contextualMeaning(
        of word: String,
        in sentence: String,
        onUpdate: @MainActor (String) -> ()
    ) async throws
        -> String {
        let service = (ActionManager.shared.translateService as? StreamService) ?? BuiltInAIService()
        let language = Defaults[.firstLanguage]
        service.customChatMessages = [
            ChatMessage(role: .system, content: systemPrompt),
            ChatMessage(role: .user, content: userPrompt(word: word, sentence: sentence, language: language)),
        ]
        // Streaming writes into `result`, which a fresh service instance does not have yet.
        _ = service.resetServiceResult()

        var answer = ""
        for try await delta in service.contentStreamTranslate(word, from: .english, to: language) {
            try Task.checkCancellation()
            answer += delta
            onUpdate(cleanedAnswer(answer))
        }
        return cleanedAnswer(answer)
    }

    // MARK: Private

    private static let systemPrompt = "You are a precise bilingual dictionary. Reply with the requested gloss only."

    private static func userPrompt(word: String, sentence: String, language: Language) -> String {
        """
        Sentence: "\(sentence)"
        Word: "\(word)"
        What does the word mean in this sentence? Answer in \(language.queryLanguageName) with a short gloss \
        of at most 12 characters or 6 words, covering the whole phrase if the word belongs to one. \
        Output the gloss only, with no quotes, explanation, or ending punctuation.
        """
    }

    @MainActor
    private static func youdaoEntry(for word: String) async throws -> Entry? {
        // A dedicated instance, because services keep per-query state in `queryModel` and `result`.
        guard let service = QueryServiceFactory.shared.service(withTypeId: ServiceType.youdao.rawValue) else {
            return nil
        }
        let queryModel = QueryModel()
        queryModel.inputText = word
        queryModel.detectedLanguage = .english

        let result = try await service.startQuery(queryModel)
        guard let wordResult = result.wordResult else {
            return nil
        }

        var entry = Entry()
        entry.phonetics = (wordResult.phonetics ?? []).compactMap { phonetic in
            guard let value = phonetic.value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else {
                return nil
            }
            return WordLookupModel.Phonetic(label: phonetic.name ?? "", value: value)
        }
        entry.senses = (wordResult.parts ?? []).compactMap { part in
            let meaning = part.means.joined(separator: "；").trimmingCharacters(in: .whitespaces)
            return meaning.isEmpty ? nil : WordLookupModel.Sense(partOfSpeech: part.part ?? "", meaning: meaning)
        }
        if entry.senses.isEmpty {
            entry.senses = (wordResult.simpleWords ?? []).prefix(3).map {
                WordLookupModel.Sense(partOfSpeech: $0.part ?? "", meaning: $0.meansText)
            }
        }
        return entry
    }

    /// A one-line definition from the dictionaries enabled in the Dictionary app, available offline.
    private static func systemDictionaryEntry(for word: String) -> Entry? {
        let range = CFRange(location: 0, length: (word as NSString).length)
        guard let definition = DCSCopyTextDefinition(nil, word as CFString, range)?.takeRetainedValue() as String?
        else {
            return nil
        }
        let summary = definition
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return Entry(senses: [WordLookupModel.Sense(partOfSpeech: "", meaning: String(summary.prefix(120)))])
    }

    /// Drops reasoning tags, surrounding quotes, and a trailing full stop from a model answer.
    private static func cleanedAnswer(_ answer: String) -> String {
        var text = answer.filterThinkTagContent().trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’「」"))
        while let last = text.last, "。.".contains(last) {
            text.removeLast()
        }
        return text
    }
}
