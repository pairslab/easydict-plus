//
//  HoverTranslationTrigger.swift
//  Easydict
//
//  Created by chenyinuo on 2026/10/21.
//  Copyright © 2026 izual. All rights reserved.
//

import AppKit
import Defaults

// MARK: - HoverTranslationTrigger

/// The modifier key held alone to translate the paragraph under the mouse.
enum HoverTranslationTrigger: String, CaseIterable, Defaults.Serializable {
    case off
    case control
    case option
    case shift

    // MARK: Internal

    /// The modifier to hold, or nil when hover translation is off.
    var modifierFlag: NSEvent.ModifierFlags? {
        switch self {
        case .off:
            nil
        case .control:
            .control
        case .option:
            .option
        case .shift:
            .shift
        }
    }
}

// MARK: CustomLocalizedStringResourceConvertible

extension HoverTranslationTrigger: CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .off:
            "setting.advance.hover_translation.trigger.off"
        case .control:
            "setting.advance.hover_translation.trigger.control"
        case .option:
            "setting.advance.hover_translation.trigger.option"
        case .shift:
            "setting.advance.hover_translation.trigger.shift"
        }
    }
}
