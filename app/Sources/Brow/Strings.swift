import Foundation

/// brow speaks English, or Ukrainian when that is the first system language.
let isUkrainian = Locale.preferredLanguages.first?.hasPrefix("uk") == true

/// Picks the text for the current language. Both versions sit at the call
/// site so a string is never missing a translation.
func tr(_ en: String, _ uk: String) -> String {
    isUkrainian ? uk : en
}

/// With BROW_DEBUG set, prints a line to stderr (events, replies, releases).
func debugLog(_ line: String) {
    guard ProcessInfo.processInfo.environment["BROW_DEBUG"] != nil else { return }
    let time = Date.now.formatted(date: .omitted, time: .standard)
    FileHandle.standardError.write(Data("\(time) \(line)\n".utf8))
}
