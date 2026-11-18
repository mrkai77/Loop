//
//  ActionBinding.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-16.
//

import Foundation
import Tome

/// A binding that others can reference by its written `id`.
/// The runtime `id` is never written. It is derived from the written id, or random without one.
protocol ActionBinding: Identifiable, Codable, Hashable, Sendable, Tome.Serializable where ID == UUID {
    /// Also keeps equal ids of different kinds from sharing an identity.
    static var bindingKind: BindingKind { get }

    /// Runtime identity, not the written id.
    var id: UUID { get set }
    /// Only present on bindings that are referenced or named.
    var configID: String? { get set }
    var target: ActionTarget { get set }
}

extension ActionBinding {
    var reference: BindingReference { .init(Self.bindingKind, referenceID) }

    /// A placeholder until the binding has a written id.
    var referenceID: String { configID ?? id.uuidString.lowercased() }

    /// The binding's name, else its action, or `link` for a reference.
    var readableIDStem: String {
        switch target {
        case let .windowAction(action):
            if action.hasCustomizableName, let name = action.name.map(ConfigurationIdentity.kebabCase), !name.isEmpty {
                return name
            }
            return action.direction.rawValue
        case .reference: return "link"
        }
    }

    /// An existing id is kept, even when the binding is renamed.
    mutating func ensureConfigurationID(avoiding taken: Set<String>) -> String {
        if let configID { return configID }
        let value = ConfigurationIdentity.nextFreeID(readableIDStem, taken: taken)
        configID = value
        return value
    }

    /// Without a written id, the random identity stays.
    mutating func deriveIdentity() {
        guard let configID else { return }
        id = ConfigurationIdentity.uuid("\(Self.bindingKind.rawValue)/id:\(configID)")
    }
}

// MARK: - Configuration

extension ActionBinding {
    static func decodeConfigurationID<Key: CodingKey>(from table: KeyedDecodingContainer<Key>, forKey key: Key) throws -> String? {
        let id = try table.decodeIfPresent(String.self, forKey: key)
        try id.map { try ConfigurationIdentity.validate($0, as: "\(bindingKind.label) id") }
        return id
    }

    /// The `id` goes first in the table, so call this before encoding other fields.
    func encodeConfigurationID<Key: CodingKey>(into table: inout KeyedEncodingContainer<Key>, forKey key: Key) throws {
        try table.encodeIfPresent(configID, forKey: key)
    }

    /// Later rows that repeat an id are renamed (see `ConfigurationIdentity.deduplicatingIDs`).
    static func tomeNormalizedElements(_ elements: [Self]) -> [Self] {
        ConfigurationIdentity.deduplicatingIDs(elements)
    }
}

// MARK: - Conflicts

extension ActionBinding {
    /// `trigger` returns `nil` for a binding without input.
    static func conflictingIDs<Trigger: Hashable>(in bindings: [Self], by trigger: (Self) -> Trigger?) -> Set<UUID> {
        // Rows that share one identity are one binding, not a conflict.
        var idsByTrigger: [Trigger: Set<UUID>] = [:]
        for binding in bindings {
            guard let trigger = trigger(binding) else { continue }
            idsByTrigger[trigger, default: []].insert(binding.id)
        }
        return idsByTrigger.values.filter { $0.count > 1 }.reduce(into: []) { $0.formUnion($1) }
    }

    static func active(in bindings: [Self], by trigger: (Self) -> (some Hashable)?) -> [Self] {
        let conflicting = conflictingIDs(in: bindings, by: trigger)
        return bindings.filter { trigger($0) != nil && !conflicting.contains($0.id) }
    }
}

// MARK: - Lists

extension Array where Element: ActionBinding {
    @discardableResult
    mutating func ensureConfigurationID(at index: Index) -> String {
        let taken = Set(compactMap(\.configID))
        return self[index].ensureConfigurationID(avoiding: taken)
    }

    /// Derives stash and cycle-step identities that survive a restart from each target's content and occurrence.
    /// Leaves out the written `id`, so assigning one can't orphan a stash.
    func identified() -> Self {
        var occurrences: [String: Int] = [:]
        return map { binding in
            var binding = binding
            let key = binding.target.contentKey
            let occurrence = occurrences[key, default: 0]
            occurrences[key] = occurrence + 1
            binding.target = binding.target.identified(seed: "\(Element.bindingKind.rawValue)/content:\(key)#\(occurrence)")
            return binding
        }
    }
}
