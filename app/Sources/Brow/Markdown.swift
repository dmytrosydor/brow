import SwiftUI

/// Just enough markdown for Claude's messages: headings, lists, code blocks,
/// rules and inline styles. AttributedString only handles the inline part.
enum MarkdownBlock: Hashable {
    case paragraph(String)
    case heading(String)
    case bullet(String)
    case numbered(String, String)
    case code(String)
    case rule

    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var code: [String]?

        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))) }
            paragraph = []
        }

        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let open = code {
                    blocks.append(.code(open.joined(separator: "\n")))
                    code = nil
                } else {
                    flush()
                    code = []
                }
            } else if code != nil {
                code?.append(raw)
            } else if line.isEmpty {
                flush()
            } else if line == "---" || line == "***" {
                flush()
                blocks.append(.rule)
            } else if let range = line.range(of: #"^#{1,6} "#, options: .regularExpression) {
                flush()
                blocks.append(.heading(String(line[range.upperBound...])))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flush()
                blocks.append(.bullet(String(line.dropFirst(2))))
            } else if let range = line.range(of: #"^\d+\. "#, options: .regularExpression) {
                flush()
                blocks.append(.numbered(String(line[..<range.upperBound]).trimmingCharacters(in: .whitespaces),
                                        String(line[range.upperBound...])))
            } else {
                paragraph.append(line)
            }
        }
        flush()
        if let open = code { blocks.append(.code(open.joined(separator: "\n"))) }
        return blocks
    }

    /// Styled text for one line or paragraph; the raw string if it does not parse.
    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    /// The message as one plain string, for previews that show a line or three.
    static func plain(_ text: String) -> String {
        parse(text).compactMap { block -> String? in
            switch block {
            case .paragraph(let s), .heading(let s), .bullet(let s), .code(let s): return String(inline(s).characters)
            case .numbered(let n, let s): return "\(n) " + String(inline(s).characters)
            case .rule: return nil
            }
        }
        .joined(separator: " ")
        .replacingOccurrences(of: "\n", with: " ")
    }
}

/// A whole message, formatted.
struct MarkdownText: View {
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MarkdownBlock.parse(text).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(Color.white.opacity(0.9))
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let s):
            Text(MarkdownBlock.inline(s))
                .fixedSize(horizontal: false, vertical: true)
        case .heading(let s):
            Text(MarkdownBlock.inline(s))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        case .bullet(let s):
            item("•", s)
        case .numbered(let n, let s):
            item(n, s)
        case .code(let s):
            Text(s)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.browGreen)
                .fixedSize(horizontal: false, vertical: true)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        case .rule:
            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(height: 1)
        }
    }

    private func item(_ mark: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(mark).foregroundStyle(Color.dim)
            Text(MarkdownBlock.inline(text))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
