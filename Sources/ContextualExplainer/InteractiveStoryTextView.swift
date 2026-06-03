import Foundation
import SwiftUI

struct InteractiveStoryTextView: View {
    var text: String
    var terms: [StoryVocabularyTerm]
    var onTermClick: (StoryVocabularyTerm) -> Void

    var body: some View {
        Text(attributedStory)
            .font(.system(size: 17))
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.openURL, OpenURLAction { url in
                guard let termID = Self.termID(from: url),
                      let term = terms.first(where: { $0.id == termID })
                else {
                    return .systemAction
                }

                onTermClick(term)
                return .handled
            })
    }

    private var attributedStory: AttributedString {
        var attributedText = AttributedString(text)
        let matches = Self.matches(in: text, terms: terms)

        for match in matches {
            guard
                let stringRange = Range(match.range, in: text),
                let attributedRange = Range(stringRange, in: attributedText),
                let url = Self.url(for: match.term)
            else {
                continue
            }

            attributedText[attributedRange].foregroundColor = .accentColor
            attributedText[attributedRange].backgroundColor = .accentColor.opacity(0.16)
            attributedText[attributedRange].link = url
        }

        return attributedText
    }

    private static func url(for term: StoryVocabularyTerm) -> URL? {
        var components = URLComponents()
        components.scheme = "contextual-explainer-story"
        components.host = "term"
        components.queryItems = [URLQueryItem(name: "id", value: term.id)]
        return components.url
    }

    private static func termID(from url: URL) -> String? {
        guard url.scheme == "contextual-explainer-story", url.host == "term" else {
            return nil
        }

        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "id" })?
            .value
    }

    private static func matches(in text: String, terms: [StoryVocabularyTerm]) -> [StoryTermMatch] {
        let nsText = text as NSString
        let sortedTerms = terms
            .filter { !$0.sample.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { lhs, rhs in
                if lhs.sample.count == rhs.sample.count {
                    return lhs.sample.localizedCaseInsensitiveCompare(rhs.sample) == .orderedAscending
                }
                return lhs.sample.count > rhs.sample.count
            }

        var occupiedRanges: [NSRange] = []
        var foundMatches: [StoryTermMatch] = []

        for term in sortedTerms {
            var searchRange = NSRange(location: 0, length: nsText.length)

            while searchRange.location < nsText.length {
                let foundRange = nsText.range(
                    of: term.sample,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    range: searchRange
                )

                guard foundRange.location != NSNotFound else { break }

                if isWordBoundaryMatch(foundRange, term: term, in: nsText),
                   !occupiedRanges.contains(where: { NSIntersectionRange($0, foundRange).length > 0 }) {
                    occupiedRanges.append(foundRange)
                    foundMatches.append(StoryTermMatch(range: foundRange, term: term))
                }

                let nextLocation = foundRange.location + max(foundRange.length, 1)
                guard nextLocation < nsText.length else { break }
                searchRange = NSRange(location: nextLocation, length: nsText.length - nextLocation)
            }
        }

        return foundMatches.sorted { lhs, rhs in
            if lhs.range.location == rhs.range.location {
                return lhs.range.length > rhs.range.length
            }
            return lhs.range.location < rhs.range.location
        }
    }

    private static func isWordBoundaryMatch(_ range: NSRange, term: StoryVocabularyTerm, in text: NSString) -> Bool {
        let sample = term.sample

        if sample.first?.isLetterOrNumber == true,
           range.location > 0,
           character(at: range.location - 1, in: text)?.isLetterOrNumber == true {
            return false
        }

        if sample.last?.isLetterOrNumber == true,
           NSMaxRange(range) < text.length,
           character(at: NSMaxRange(range), in: text)?.isLetterOrNumber == true {
            return false
        }

        return true
    }

    private static func character(at location: Int, in text: NSString) -> Character? {
        guard location >= 0, location < text.length else { return nil }
        return Character(text.substring(with: NSRange(location: location, length: 1)))
    }
}

private struct StoryTermMatch {
    var range: NSRange
    var term: StoryVocabularyTerm
}

private extension Character {
    var isLetterOrNumber: Bool {
        unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
    }
}
