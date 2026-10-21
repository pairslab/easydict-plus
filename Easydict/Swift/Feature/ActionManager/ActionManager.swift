//
//  ActionManager.swift
//  Easydict
//
//  Created by tisfeng on 2025/8/29.
//  Copyright © 2025 izual. All rights reserved.
//

import AppKit
import Defaults
import Foundation
import SelectedTextKit

// MARK: - ActionManager

/// Singleton class responsible for handling various application actions
@objc(EZActionManager)
class ActionManager: NSObject {
    // MARK: Internal

    // MARK: - Singleton

    @objc static let shared = ActionManager()

    var polishService = PolishingService()

    /// Service used to translate text in place, chosen in Advanced settings.
    ///
    /// Falls back to the built-in AI service when no service is configured or it no longer exists.
    var translateService: QueryService {
        let typeID = Defaults[.textReplacementServiceTypeID]
        if !typeID.isEmpty, let service = QueryServiceFactory.shared.service(withTypeId: typeID) {
            return service
        }
        return BuiltInAIService()
    }

    // MARK: - Public Methods

    /// Translate selected text and replace it with the translation result
    @MainActor
    func translateAndReplace() async {
        logInfo("Translate and Replace")
        await executeTextReplacementAction(.translate)
    }

    /// Polish selected text and replace it with the polished result
    @MainActor
    func polishAndReplace() async {
        logInfo("Polish and Replace")
        await executeTextReplacementAction(.polish)
    }

    /// Translate the input of the showing query window and insert it into the previous app.
    ///
    /// The window closes first so focus returns to the app the user was typing in. A finished
    /// first result for the same input is inserted directly; otherwise the text is translated
    /// with the text replacement service while the preview streams it next to the caret.
    @MainActor
    func insertQueryTranslation() async {
        let windowManager = EZWindowManager.shared()
        guard let queryViewController = windowManager.floatingWindow?.queryViewController else {
            return
        }

        let inputText = queryViewController.inputText.trim()
        guard !inputText.isEmpty else {
            NSSound.beep()
            return
        }

        let isResultForInput = queryViewController.queryModel.queryText.trim() == inputText
        let finishedText = isResultForInput ? queryViewController.firstFinishedTranslatedText()?.trim() : nil

        windowManager.closeFloatingWindow()
        guard await waitForPreviousAppActivation() else {
            // No other app took focus, so there is nowhere to insert; keep the result reachable.
            logInfo("Previous app was not reactivated, copy translation instead of inserting")
            finishedText?.copyToPasteboard()
            return
        }

        let target = insertionTarget(for: systemUtility.focusedElementInfoForInsertion())
        if let finishedText, !finishedText.isEmpty {
            logInfo("Insert finished translation into previous app")
            await insert(finishedText, into: target)
            return
        }

        await processAndWriteBack(
            inputText,
            type: .translate,
            service: translateService,
            target: target,
            outcome: .inserted
        )
    }

    // MARK: Private

    /// Type of text processing action
    private enum ProcessingType {
        case translate
        case polish
    }

    /// Where processed text is written back.
    private struct InsertionTarget {
        /// App that owned the focused element when the action started.
        let processIdentifier: pid_t?
        let strategies: [TextStrategy]
        /// Whether insertion writes through Accessibility instead of the pasteboard.
        let isSupportedAX: Bool

        /// Whether the original app still has focus, so inserting will not land elsewhere.
        var isFrontmost: Bool {
            NSWorkspace.shared.frontmostApplication?.processIdentifier == processIdentifier
        }
    }

    /// How long a finished preview stays visible.
    private enum PreviewDuration {
        static let success: TimeInterval = 0.9
        static let copied: TimeInterval = 2.2
        static let failure: TimeInterval = 3.5
    }

    private let systemUtility = SystemUtility.shared

    // MARK: - Core Action Methods

    /// Common method to execute text replacement actions
    @MainActor
    private func executeTextReplacementAction(_ type: ProcessingType) async {
        let enableSelectAll = Defaults[.autoSelectAllTextFieldText]
        let elementInfo = await systemUtility.focusedElementInfo(enableSelectAll: enableSelectAll)

        var queryText = elementInfo.focusedText
        if queryText?.isEmpty ?? true {
            queryText = await systemUtility.getSelectedText()
        }

        guard let queryText = queryText?.trim(), !queryText.isEmpty else {
            logInfo("No text selected or focused for \(type), skipping action")
            NSSound.beep()
            return
        }

        let service = type == .translate ? translateService : polishService
        await processAndWriteBack(
            queryText,
            type: type,
            service: service,
            target: insertionTarget(for: elementInfo),
            outcome: .replaced
        )
    }

    /// Process `queryText` with `service` and write the result back in a single insertion.
    ///
    /// Keeping the original text until the result is complete means a failed or cancelled
    /// request never leaves half-replaced text behind. The preview, when enabled, streams
    /// the result meanwhile. If focus moved to another app, the result is copied instead.
    @MainActor
    private func processAndWriteBack(
        _ queryText: String,
        type: ProcessingType,
        service: QueryService,
        target: InsertionTarget,
        outcome: TextReplacementPreviewModel.Outcome
    ) async {
        let preview = presentPreviewIfEnabled(for: service, type: type)

        do {
            let processedText = try await processText(queryText, type: type, service: service) { text in
                preview?.text = text
            }
            guard !processedText.isEmpty else {
                throw QueryError(type: .noResult)
            }
            preview?.text = processedText

            if target.isFrontmost {
                await insert(processedText, into: target)
                finishPreview(preview, phase: .completed(outcome), after: PreviewDuration.success)
            } else {
                logInfo("Focus moved to another app, copy processed text instead of inserting")
                processedText.copyToPasteboard()
                finishPreview(preview, phase: .completed(.copied), after: PreviewDuration.copied)
            }
        } catch is CancellationError {
            logInfo("Text processing cancelled")
            TextReplacementPreviewPanel.shared.dismiss()
        } catch {
            logError("Text processing failed: \(error)")
            finishPreview(preview, phase: .failed(failureMessage(for: error)), after: PreviewDuration.failure)
        }
    }

    // MARK: - Processing

    /// Translate or polish `queryText`, reporting the accumulated text after each streamed chunk.
    ///
    /// Stream services are asked for a plain translation so short input is not expanded into a
    /// dictionary entry; other services return their final translation once.
    @MainActor
    private func processText(
        _ queryText: String,
        type: ProcessingType,
        service: QueryService,
        onUpdate: @MainActor (String) -> ()
    ) async throws
        -> String {
        let queryModel = try await DetectManager().detectText(queryText)
        let sourceLanguage = queryModel.detectedLanguage
        let targetLanguage = queryModel.queryTargetLanguage
        logInfo("\(type) with \(service.serviceTypeWithUniqueIdentifier()): \(sourceLanguage) -> \(targetLanguage)")

        guard let streamService = service as? StreamService else {
            let result = try await service.startQuery(queryModel)
            if let error = result.error {
                throw error
            }
            return (result.translatedText ?? "").trim()
        }

        logInfo("Using model: \(streamService.model)")
        let request = TranslationRequest(
            text: queryText,
            sourceLanguage: sourceLanguage.code,
            targetLanguage: targetLanguage.code,
            serviceType: streamService.serviceTypeWithUniqueIdentifier(),
            queryType: .translation
        )

        var accumulatedText = ""
        for try await content in try await streamService.contentStreamTranslate(request: request) {
            try Task.checkCancellation()
            accumulatedText += content
            onUpdate(accumulatedText.filterThinkTagContent().trim())
        }
        return accumulatedText.filterThinkTagContent().trim()
    }

    // MARK: - Insertion

    /// Insertion strategies for the focused element, falling back to pasting when
    /// Accessibility cannot write to it instead of silently doing nothing.
    private func insertionTarget(for elementInfo: FocusedElementInfo) -> InsertionTarget {
        var strategies = systemUtility.textStrategies(for: elementInfo)
        if strategies.isEmpty {
            strategies = [.shortcut]
        }
        return InsertionTarget(
            processIdentifier: NSWorkspace.shared.frontmostApplication?.processIdentifier,
            strategies: strategies,
            isSupportedAX: elementInfo.isSupportedAXElement
        )
    }

    /// Insert `text` at the target, restoring the user's pasteboard when pasting was needed.
    ///
    /// - Note: For GitHub web text area, if select all and insert empty string,
    ///   it will clear the text area and lose focus. So we never insert empty string.
    @MainActor
    private func insert(_ text: String, into target: InsertionTarget) async {
        guard !text.isEmpty else {
            return
        }

        let pasteboard = NSPasteboard.general
        let snapshotItems = target.isSupportedAX ? nil : pasteboard.backupItems()

        await systemUtility.insertText(text, using: target.strategies)
        logInfo("Inserted text using \(target.strategies): \(text.prettyJSONString)")

        if let snapshotItems {
            pasteboard.restoreItems(snapshotItems)
        }
    }

    /// Wait until the app that was frontmost before the query window regains focus.
    ///
    /// - Returns: Whether another app became frontmost within the timeout.
    @MainActor
    private func waitForPreviousAppActivation() async -> Bool {
        let ownBundleID = Bundle.main.bundleIdentifier
        for _ in 0 ..< 20 {
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier != ownBundleID {
                // Give the reactivated app a moment to restore its focused text element.
                await Task.sleep(seconds: 0.08)
                return true
            }
            await Task.sleep(seconds: 0.03)
        }
        return false
    }

    // MARK: - Preview

    @MainActor
    private func presentPreviewIfEnabled(
        for service: QueryService,
        type: ProcessingType
    )
        -> TextReplacementPreviewModel? {
        guard Defaults[.showTextReplacementPreview] else {
            return nil
        }

        let model = TextReplacementPreviewModel(
            serviceName: service.name(),
            serviceIconName: service.iconName(),
            activity: type == .translate ? .translating : .polishing
        )
        TextReplacementPreviewPanel.shared.present(
            model,
            anchorRect: systemUtility.focusedTextCaretRect()
        )
        return model
    }

    @MainActor
    private func finishPreview(
        _ preview: TextReplacementPreviewModel?,
        phase: TextReplacementPreviewModel.Phase,
        after duration: TimeInterval
    ) {
        guard let preview else {
            return
        }
        preview.phase = phase
        TextReplacementPreviewPanel.shared.dismiss(after: duration)
    }

    /// A short, readable reason for the preview, preferring the service's own message.
    private func failureMessage(for error: Error) -> String {
        guard let queryError = error as? QueryError else {
            return error.localizedDescription
        }

        let details = [queryError.message, queryError.errorDataMessage]
            .compactMap { $0?.trim() }
            .filter { !$0.isEmpty }
        return details.isEmpty ? queryError.type.localizedDescription : details.joined(separator: "\n")
    }
}
