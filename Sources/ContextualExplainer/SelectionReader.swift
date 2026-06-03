import AppKit
import ApplicationServices
import Foundation

struct SelectionPayload: Equatable {
    var selection: String
    var context: String
    var note: String?
}

@MainActor
final class SelectionReader {
    private(set) var lastContextWarning: String?

    func readSelection() async throws -> SelectionPayload {
        if let payload = readAccessibilitySelection(), !payload.selection.isEmpty {
            return payload
        }

        if !isAccessibilityTrusted(prompt: true) {
            throw ExplainerError.noText
        }

        if let payload = await readByCopyShortcut(), !payload.selection.isEmpty {
            return payload
        }

        throw ExplainerError.noText
    }

    func readBestSelectionAfterCopy(preferredSelection: String?) async -> SelectionPayload? {
        lastContextWarning = nil
        let preferred = preferredSelection?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let payload = readBrowserSelection(preferredSelection: preferredSelection), !payload.selection.isEmpty {
            return payload
        }
        let browserWarning = lastContextWarning

        if let payload = readAccessibilitySelection(preferredSelection: preferredSelection), !payload.selection.isEmpty {
            return payload.withFallbackNote(browserWarning)
        }

        if let payload = await readExpandedKeyboardContext(preferredSelection: preferred), !payload.selection.isEmpty {
            return payload
        }

        if let payload = readClipboard(), !payload.selection.isEmpty {
            return payload.withFallbackNote(browserWarning)
        }

        return await readByCopyShortcut()?.withFallbackNote(browserWarning)
    }

    func readClipboard() -> SelectionPayload? {
        guard
            let string = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !string.isEmpty
        else {
            return nil
        }
        return SelectionPayload(selection: string, context: string)
    }

    private func readAccessibilitySelection(preferredSelection: String? = nil) -> SelectionPayload? {
        guard isAccessibilityTrusted(prompt: false) else { return nil }

        let systemElement = AXUIElementCreateSystemWide()
        var focusedObject: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(systemElement, kAXFocusedUIElementAttribute as CFString, &focusedObject)
        guard focusedStatus == .success, let focusedElement = focusedObject else { return nil }

        let element = focusedElement as! AXUIElement
        let preferred = preferredSelection?.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = candidateElements(around: element)
        var fallbackPayload: SelectionPayload?

        for candidate in candidates {
            guard
                let selectedText = copyStringAttribute(kAXSelectedTextAttribute, from: candidate),
                let payload = makePayload(selection: selectedText, from: candidate, preferredSelection: preferred)
            else {
                continue
            }

            if !payload.context.caseInsensitiveEquals(payload.selection) {
                return payload
            }
            fallbackPayload = payload
        }

        if let preferred, !preferred.isEmpty {
            for candidate in candidates {
                if let payload = makePayload(selection: preferred, from: candidate, preferredSelection: preferred) {
                    if !payload.context.caseInsensitiveEquals(payload.selection) {
                        return payload
                    }
                    fallbackPayload = payload
                }
            }

            if let mergedContext = mergedContextAround(selection: preferred, from: candidates) {
                return SelectionPayload(selection: preferred, context: mergedContext)
            }
        }

        return fallbackPayload
    }

    private func makePayload(selection rawSelection: String, from element: AXUIElement, preferredSelection: String?) -> SelectionPayload? {
        let selection = rawSelection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selection.isEmpty else { return nil }

        if
            let preferredSelection,
            !preferredSelection.isEmpty,
            !selection.caseInsensitiveEquals(preferredSelection)
        {
            return nil
        }

        let textSources = contextTextCandidates(for: element, selection: selection)

        if let selectedRange = copySelectedRange(from: element) {
            for fullText in textSources {
                if let sentence = fullText.sentenceAround(range: selectedRange) {
                    return SelectionPayload(selection: selection, context: sentence)
                }
            }
        }

        for fullText in textSources {
            if let sentence = fullText.sentenceAround(firstOccurrenceOf: selection) {
                return SelectionPayload(selection: selection, context: sentence)
            }
        }

        return SelectionPayload(selection: selection, context: selection)
    }

    private func readBrowserSelection(preferredSelection: String?) -> SelectionPayload? {
        guard
            let application = NSWorkspace.shared.frontmostApplication,
            let bundleID = application.bundleIdentifier,
            let appName = application.localizedName
        else {
            return nil
        }

        let result: AppleScriptResult
        if Self.chromiumBrowserBundleIDs.contains(bundleID) {
            result = runAppleScript("""
            tell application "\(appName.appleScriptEscaped())"
                if not (exists front window) then return ""
                return execute active tab of front window javascript "\(Self.browserSelectionJavaScript.appleScriptEscaped())"
            end tell
            """)
        } else if bundleID == "com.apple.Safari" {
            result = runAppleScript("""
            tell application "\(appName.appleScriptEscaped())"
                if not (exists front window) then return ""
                return do JavaScript "\(Self.browserSelectionJavaScript.appleScriptEscaped())" in current tab of front window
            end tell
            """)
        } else {
            return nil
        }

        if let message = result.error {
            lastContextWarning = Self.browserContextWarning(appName: appName, message: message)
            return nil
        }
        let output = result.output

        guard
            let data = output.data(using: .utf8),
            let payload = try? JSONDecoder().decode(BrowserSelectionPayload.self, from: data)
        else {
            lastContextWarning = "Could not read the selected sentence from \(appName)."
            return nil
        }

        let selection = payload.selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selection.isEmpty else { return nil }

        if
            let preferredSelection,
            !preferredSelection.isEmpty,
            !selection.caseInsensitiveEquals(preferredSelection)
        {
            return nil
        }

        let context = payload.context.trimmingCharacters(in: .whitespacesAndNewlines)
        return SelectionPayload(selection: selection, context: context.isEmpty ? selection : context)
    }

    private func runAppleScript(_ source: String) -> AppleScriptResult {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            return AppleScriptResult(output: "", error: "Could not build the browser context script.")
        }
        let output = script.executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "\(error)"
            NSLog("Browser context AppleScript failed: \(message)")
            return AppleScriptResult(output: "", error: message)
        }
        return AppleScriptResult(output: output.stringValue ?? "", error: nil)
    }

    private func candidateElements(around focusedElement: AXUIElement) -> [AXUIElement] {
        var result: [AXUIElement] = []
        var seen = Set<AXElementID>()

        func append(_ element: AXUIElement) {
            let id = AXElementID(element)
            guard !seen.contains(id) else { return }
            seen.insert(id)
            result.append(element)
        }

        append(focusedElement)

        if let frontmostApplication = NSWorkspace.shared.frontmostApplication {
            let appElement = AXUIElementCreateApplication(frontmostApplication.processIdentifier)
            append(appElement)

            if let focusedWindow = copyElementAttribute(kAXFocusedWindowAttribute, from: appElement) {
                append(focusedWindow)
            }

            for window in copyElementArrayAttribute(kAXWindowsAttribute, from: appElement) {
                append(window)
            }
        }

        var current = focusedElement
        for _ in 0..<3 {
            guard let parent = copyElementAttribute(kAXParentAttribute, from: current) else { break }
            append(parent)
            current = parent
        }

        var queue = result
        var visitedChildren = 0
        while !queue.isEmpty && visitedChildren < 600 {
            let element = queue.removeFirst()
            for child in copyElementArrayAttribute(kAXChildrenAttribute, from: element) {
                append(child)
                queue.append(child)
                visitedChildren += 1
                if visitedChildren >= 600 { break }
            }
        }

        return result
    }

    private func contextTextCandidates(for element: AXUIElement, selection: String) -> [String] {
        var values: [String] = []
        var seen = Set<String>()

        func append(_ value: String?) {
            guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
            guard !seen.contains(text) else { return }
            seen.insert(text)
            values.append(text)
        }

        append(copyStringAttribute(kAXValueAttribute, from: element))
        append(copyStringAttribute(kAXDescriptionAttribute, from: element))
        append(copyStringAttribute(kAXTitleAttribute, from: element))

        var current = element
        for _ in 0..<3 {
            guard let parent = copyElementAttribute(kAXParentAttribute, from: current) else { break }
            append(copyStringAttribute(kAXValueAttribute, from: parent))
            append(copyStringAttribute(kAXDescriptionAttribute, from: parent))
            append(copyStringAttribute(kAXTitleAttribute, from: parent))
            current = parent
        }

        return values.sorted { lhs, rhs in
            let lhsContains = lhs.localizedCaseInsensitiveContains(selection)
            let rhsContains = rhs.localizedCaseInsensitiveContains(selection)
            if lhsContains != rhsContains {
                return lhsContains
            }
            return lhs.count > rhs.count
        }
    }

    private func mergedContextAround(selection: String, from elements: [AXUIElement]) -> String? {
        var snippets: [String] = []
        var seen = Set<String>()

        for element in elements {
            for text in primaryTextCandidates(for: element) {
                let cleaned = text.normalizedForSelectionCompare()
                guard !cleaned.isEmpty else { continue }
                guard cleaned.count <= 500 else { continue }
                guard !seen.contains(cleaned) else { continue }
                seen.insert(cleaned)
                snippets.append(cleaned)
            }
        }

        guard !snippets.isEmpty else { return nil }

        let exactIndexes = snippets.indices.filter { snippets[$0].caseInsensitiveEquals(selection) }
        let containingIndexes = snippets.indices.filter { snippets[$0].localizedCaseInsensitiveContains(selection) }
        let indexes = exactIndexes.isEmpty ? containingIndexes : exactIndexes

        for index in indexes {
            let start = max(snippets.startIndex, index - 8)
            let end = min(snippets.endIndex, index + 9)
            let merged = snippets[start..<end].joined(separator: " ")

            if let sentence = merged.sentenceAround(firstOccurrenceOf: selection),
               !sentence.caseInsensitiveEquals(selection) {
                return sentence
            }
        }

        return nil
    }

    private func primaryTextCandidates(for element: AXUIElement) -> [String] {
        [
            copyStringAttribute(kAXValueAttribute, from: element),
            copyStringAttribute(kAXDescriptionAttribute, from: element),
            copyStringAttribute(kAXTitleAttribute, from: element)
        ]
        .compactMap { $0 }
    }

    private func copyStringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard status == .success else { return nil }
        return value as? String
    }

    private func copyElementAttribute(_ attribute: String, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard status == .success, let value else { return nil }
        return (value as! AXUIElement)
    }

    private func copyElementArrayAttribute(_ attribute: String, from element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard status == .success, let array = value as? [Any] else { return [] }
        return array.compactMap { item in
            guard CFGetTypeID(item as CFTypeRef) == AXUIElementGetTypeID() else { return nil }
            return (item as! AXUIElement)
        }
    }

    private func copySelectedRange(from element: AXUIElement) -> NSRange? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value)
        guard status == .success, let axValue = value else { return nil }

        var cfRange = CFRange()
        let didRead = AXValueGetValue(axValue as! AXValue, .cfRange, &cfRange)
        guard didRead else { return nil }
        return NSRange(location: cfRange.location, length: cfRange.length)
    }

    private func readByCopyShortcut() async -> SelectionPayload? {
        let pasteboard = NSPasteboard.general
        let savedItems = pasteboard.pasteboardItems ?? []
        let originalChangeCount = pasteboard.changeCount

        sendCopyShortcut()

        for _ in 0..<12 {
            try? await Task.sleep(nanoseconds: 60_000_000)
            if pasteboard.changeCount != originalChangeCount {
                break
            }
        }

        let copied = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
        restorePasteboard(savedItems)

        guard let copied, !copied.isEmpty else { return nil }
        return SelectionPayload(selection: copied, context: copied)
    }

    private func readExpandedKeyboardContext(preferredSelection: String?) async -> SelectionPayload? {
        guard !NSApp.isActive else { return nil }
        guard let selection = preferredSelection, !selection.isEmpty else { return nil }

        let pasteboard = NSPasteboard.general
        let savedItems = pasteboard.pasteboardItems ?? []
        let savedChangeCount = pasteboard.changeCount
        let selectedWordCount = max(1, selection.contextWordCount)

        sendKey(.left)
        await shortPause()
        sendWordMove(.left, count: 12, extendingSelection: true)
        guard let leftContext = await copyCurrentSelectionIgnoring(changeCount: savedChangeCount) else {
            restorePasteboard(savedItems)
            return nil
        }

        sendKey(.right)
        await shortPause()
        sendWordMove(.right, count: selectedWordCount, extendingSelection: false)
        await shortPause()
        sendWordMove(.right, count: 12, extendingSelection: true)
        let rightContext = await copyCurrentSelectionIgnoring(changeCount: pasteboard.changeCount)

        restorePasteboard(savedItems)

        let context = expandedContext(selection: selection, left: leftContext, right: rightContext)
        guard !context.caseInsensitiveEquals(selection) else { return nil }
        return SelectionPayload(selection: selection, context: context)
    }

    private func expandedContext(selection: String, left: String?, right: String?) -> String {
        let parts = [
            left?.trimmingCharacters(in: .whitespacesAndNewlines),
            selection.trimmingCharacters(in: .whitespacesAndNewlines),
            right?.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }

        let merged = parts.joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return merged.sentenceAround(firstOccurrenceOf: selection) ?? merged
    }

    private func copyCurrentSelectionIgnoring(changeCount: Int) async -> String? {
        let pasteboard = NSPasteboard.general
        sendCopyShortcut()

        for _ in 0..<12 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if pasteboard.changeCount != changeCount {
                break
            }
        }

        let copied = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let copied, !copied.isEmpty else { return nil }
        return copied
    }

    private func sendCopyShortcut() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyCodeForC: CGKeyCode = 8
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCodeForC, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCodeForC, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private func sendWordMove(_ direction: ArrowKey, count: Int, extendingSelection: Bool) {
        guard count > 0 else { return }
        for _ in 0..<count {
            var flags: CGEventFlags = [.maskAlternate]
            if extendingSelection {
                flags.insert(.maskShift)
            }
            sendKey(direction, flags: flags)
            Thread.sleep(forTimeInterval: 0.012)
        }
    }

    private func sendKey(_ key: ArrowKey, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: key.keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: key.keyCode, keyDown: false)
        keyDown?.flags = flags
        keyUp?.flags = flags
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private func shortPause() async {
        try? await Task.sleep(nanoseconds: 80_000_000)
    }

    private func restorePasteboard(_ items: [NSPasteboardItem]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }

    private func isAccessibilityTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

private enum ArrowKey {
    case left
    case right

    var keyCode: CGKeyCode {
        switch self {
        case .left:
            return 123
        case .right:
            return 124
        }
    }
}

private struct BrowserSelectionPayload: Decodable {
    var selection: String
    var context: String
}

private struct AppleScriptResult {
    var output: String
    var error: String?
}

private extension SelectionPayload {
    func withFallbackNote(_ note: String?) -> SelectionPayload {
        guard
            let note,
            context.caseInsensitiveEquals(selection)
        else {
            return self
        }

        return SelectionPayload(selection: selection, context: context, note: note)
    }
}

private extension String {
    func appleScriptEscaped() -> String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
    }

    func caseInsensitiveEquals(_ other: String) -> Bool {
        normalizedForSelectionCompare().localizedCaseInsensitiveCompare(other.normalizedForSelectionCompare()) == .orderedSame
    }

    func localizedCaseInsensitiveContains(_ other: String) -> Bool {
        normalizedForSelectionCompare().range(
            of: other.normalizedForSelectionCompare(),
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil
    }

    func normalizedForSelectionCompare() -> String {
        components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var contextWordCount: Int {
        let matches = range(of: "\\S+", options: .regularExpression)
        guard matches != nil else { return 0 }
        var count = 0
        var searchRange = startIndex..<endIndex
        while let range = self.range(of: "\\S+", options: .regularExpression, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<endIndex
        }
        return count
    }

    func sentenceAround(range nsRange: NSRange) -> String? {
        guard let swiftRange = Range(nsRange, in: self) else { return nil }
        return sentenceAround(swiftRange: swiftRange)
    }

    func sentenceAround(firstOccurrenceOf selection: String) -> String? {
        guard
            let range = range(of: selection, options: [.caseInsensitive, .diacriticInsensitive])
        else {
            return nil
        }
        return sentenceAround(swiftRange: range)
    }

    private func sentenceAround(swiftRange: Range<String.Index>) -> String? {
        let searchStart = self[..<swiftRange.lowerBound]
        let searchEnd = self[swiftRange.upperBound...]

        let sentenceStart = searchStart.lastIndex(where: { ".!?。！？\n".contains($0) })
            .map { index(after: $0) } ?? startIndex
        let sentenceEnd = searchEnd.firstIndex(where: { ".!?。！？\n".contains($0) }) ?? endIndex

        let sentence = self[sentenceStart..<sentenceEnd].trimmingCharacters(in: .whitespacesAndNewlines)
        return sentence.isEmpty ? nil : sentence
    }
}

private extension SelectionReader {
    static let chromiumBrowserBundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "company.thebrowser.Browser",
        "com.openai.atlas"
    ]

    static func browserContextWarning(appName: String, message: String) -> String {
        if message.localizedCaseInsensitiveContains("Executing JavaScript through AppleScript is turned off") {
            return "To read webpage context from \(appName), turn on View > Developer > Allow JavaScript from Apple Events, then try Command+C twice again."
        }

        if message.localizedCaseInsensitiveContains("not authorized") || message.localizedCaseInsensitiveContains("not allowed") {
            return "macOS blocked browser automation for \(appName). Open System Settings > Privacy & Security > Automation and allow ContextualExplainer to control \(appName)."
        }

        return "Could not read webpage context from \(appName): \(message)"
    }

    static let browserSelectionJavaScript = """
    (() => {
      const selection = window.getSelection();
      if (!selection || selection.rangeCount === 0) {
        return JSON.stringify({ selection: "", context: "" });
      }

      const selected = selection.toString().replace(/\\s+/g, " ").trim();
      if (!selected) {
        return JSON.stringify({ selection: "", context: "" });
      }

      const range = selection.getRangeAt(0);
      const stopTags = new Set(["SCRIPT", "STYLE", "NOSCRIPT", "SVG", "CANVAS", "IFRAME"]);
      const blockTags = new Set(["P", "LI", "TD", "TH", "H1", "H2", "H3", "H4", "H5", "H6", "BLOCKQUOTE", "FIGCAPTION", "LABEL", "BUTTON", "A", "SPAN", "DIV", "SECTION", "ARTICLE"]);

      function clean(text) {
        return (text || "").replace(/\\s+/g, " ").trim();
      }

      function contains(text, needle) {
        return clean(text).toLocaleLowerCase().includes(clean(needle).toLocaleLowerCase());
      }

      function nearestTextContainer(node) {
        let el = node.nodeType === Node.TEXT_NODE ? node.parentElement : node;
        let best = "";

        while (el && el !== document.documentElement) {
          if (el.tagName && !stopTags.has(el.tagName)) {
            const text = clean(el.innerText || el.textContent || "");
            if (text && contains(text, selected)) {
              best = text;
              if (blockTags.has(el.tagName) && text.length <= 1200) {
                return text;
              }
            }
          }
          el = el.parentElement;
        }

        return best || clean(document.body?.innerText || document.body?.textContent || "");
      }

      function sentenceAround(text, needle) {
        const normalized = clean(text);
        const folded = normalized.toLocaleLowerCase();
        const query = clean(needle).toLocaleLowerCase();
        let index = folded.indexOf(query);

        if (index < 0) {
          return normalized.slice(0, 500);
        }

        let start = index;
        while (start > 0 && !/[.!?。！？\\n]/.test(normalized[start - 1])) {
          start -= 1;
        }

        let end = index + query.length;
        while (end < normalized.length && !/[.!?。！？\\n]/.test(normalized[end])) {
          end += 1;
        }
        if (end < normalized.length) {
          end += 1;
        }

        return normalized.slice(start, end).trim();
      }

      const sourceText = nearestTextContainer(range.commonAncestorContainer);
      const context = sentenceAround(sourceText, selected);
      return JSON.stringify({ selection: selected, context });
    })();
    """
}

private struct AXElementID: Hashable {
    private let rawValue: UInt

    init(_ element: AXUIElement) {
        rawValue = UInt(bitPattern: Unmanaged.passUnretained(element).toOpaque())
    }
}
