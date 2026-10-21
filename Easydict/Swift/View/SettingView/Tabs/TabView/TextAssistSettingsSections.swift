//
//  TextAssistSettingsSections.swift
//  Easydict
//
//  Created by chenyinuo on 2026/10/21.
//  Copyright © 2026 izual. All rights reserved.
//

import Defaults
import SFSafeSymbols
import SwiftUI

// MARK: - TextReplacementSettingsSection

/// Advanced settings for translate-and-replace and insert-translation.
struct TextReplacementSettingsSection: View {
    // MARK: Internal

    var body: some View {
        Section {
            Picker(
                selection: $textReplacementServiceTypeID,
                label: AdvancedTabItemView(
                    color: .indigo,
                    icon: .arrowLeftArrowRightSquare,
                    labelText: "setting.advance.text_replacement.service",
                    subtitleText: "setting.advance.text_replacement.service_desc"
                )
            ) {
                Text("setting.advance.text_replacement.service.built_in_ai")
                    .tag("")
                Divider()
                ForEach(serviceOptions) { option in
                    Text(option.title)
                        .tag(option.typeID)
                }
            }
            Toggle(isOn: $showTextReplacementPreview) {
                AdvancedTabItemView(
                    color: .cyan,
                    icon: .textMagnifyingglass,
                    labelText: "setting.advance.text_replacement.show_preview",
                    subtitleText: "setting.advance.text_replacement.show_preview_desc"
                )
            }
        } header: {
            Text("setting.advance.header.text_replacement")
        }
        .onAppear {
            serviceOptions = TextReplacementServiceOption.availableOptions()
        }
    }

    // MARK: Private

    @State private var serviceOptions: [TextReplacementServiceOption] = []

    @Default(.textReplacementServiceTypeID) private var textReplacementServiceTypeID
    @Default(.showTextReplacementPreview) private var showTextReplacementPreview
}

// MARK: - ReadingAssistSettingsSection

/// Advanced settings for reading foreign text: word lookup and paragraph hover translation.
struct ReadingAssistSettingsSection: View {
    // MARK: Internal

    var body: some View {
        Section {
            Toggle(isOn: $enableWordLookup) {
                AdvancedTabItemView(
                    color: .mint,
                    icon: .characterBookClosed,
                    labelText: "setting.advance.word_lookup.enable",
                    subtitleText: "setting.advance.word_lookup.enable_desc"
                )
            }
            Picker(
                selection: $hoverTranslationTrigger,
                label: AdvancedTabItemView(
                    color: .teal,
                    icon: .cursorarrowRays,
                    labelText: "setting.advance.hover_translation.trigger",
                    subtitleText: "setting.advance.hover_translation.trigger_desc"
                )
            ) {
                ForEach(HoverTranslationTrigger.allCases, id: \.rawValue) { trigger in
                    Text(trigger.localizedStringResource)
                        .tag(trigger)
                }
            }
        } header: {
            Text("setting.advance.header.reading_assist")
        }
    }

    // MARK: Private

    @Default(.enableWordLookup) private var enableWordLookup
    @Default(.hoverTranslationTrigger) private var hoverTranslationTrigger
}
