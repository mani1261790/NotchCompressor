import Foundation

/// Persist keys and values, never a sentence rendered in the previous language.
public struct LocalizedMessage: Codable, Equatable, Sendable {
    public let key: String
    public let arguments: [String]
    public init(_ key: String, _ arguments: String...) {
        self.key = key
        self.arguments = arguments
    }
    public var text: String { L10n.render(key, arguments: arguments) }
}

public enum L10n {
    // Scoped overrides make tests independent without mutable global language state.
    @TaskLocal public static var languageOverride: String?
    public static var language: String {
        languageOverride ?? resolveLanguage(Locale.preferredLanguages)
    }
    public static func resolveLanguage(_ preferences: [String]) -> String {
        Bundle.preferredLocalizations(from: ["en", "ja"], forPreferences: preferences).first ?? "en"
    }
    public static var locale: Locale { Locale(identifier: language == "ja" ? "ja_JP" : "en_US") }
    static func bundle(_ language: String) -> Bundle {
        guard let path = Bundle.module.path(forResource: language, ofType: "lproj"),
            let bundle = Bundle(path: path)
        else { preconditionFailure("Missing localization bundle: \(language)") }
        return bundle
    }
    public static func text(_ key: String, _ arguments: String...) -> String {
        render(key, arguments: arguments)
    }
    static func render(_ key: String, arguments: [String]) -> String {
        let english = bundle("en").localizedString(forKey: key, value: "Message unavailable.", table: nil)
        let template = bundle(language).localizedString(forKey: key, value: english, table: nil)
        return String(format: template, locale: locale, arguments: arguments)
    }
    public static func bytes(_ count: Int64) -> String {
        ByteCountFormatStyle(style: .file, spellsOutZero: false, locale: locale).format(count)
    }
    public static func integer(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }
}
