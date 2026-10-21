//
//  TextReplacementServiceOption.swift
//  Easydict
//
//  Created by chenyinuo on 2026/10/21.
//  Copyright © 2026 izual. All rights reserved.
//

import Foundation

// MARK: - TextReplacementServiceOption

/// A translation service that can be chosen for translate-and-replace in settings.
struct TextReplacementServiceOption: Identifiable, Hashable {
    // MARK: Internal

    /// Service type ID, including the instance UUID for services that allow several instances.
    let typeID: String
    let title: String

    var id: String { typeID }

    /// Translation services listed in any query window, in their display order.
    ///
    /// Dictionaries and the built-in AI tools are excluded; the built-in AI translator is
    /// offered separately as the default choice.
    static func availableOptions() -> [TextReplacementServiceOption] {
        let storage = LocalStorage.shared()
        let windowTypes: [EZWindowType] = [.mini, .fixed, .main]

        var seenTypeIDs = Set<String>()
        let typeIDs = windowTypes
            .flatMap { storage.allServiceTypes($0) }
            .filter { seenTypeIDs.insert($0).inserted }

        return typeIDs.compactMap { typeID in
            guard let metadata = QueryServiceFactory.shared.metadata(withTypeId: typeID),
                  !excludedServiceTypes.contains(metadata.serviceType)
            else {
                return nil
            }
            return TextReplacementServiceOption(typeID: typeID, title: metadata.title)
        }
    }

    // MARK: Private

    private static let excludedServiceTypes: Set<ServiceType> = [
        .appleDictionary,
        .mDict,
        .builtInAI,
        .polishing,
        .summary,
    ]
}
