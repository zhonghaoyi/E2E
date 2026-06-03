import AppKit
import SwiftUI

struct SelectableExplanationTextView: NSViewRepresentable {
    var text: String
    var onSelection: (String?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelection: onSelection)
    }

    func makeNSView(context: Context) -> IntrinsicTextView {
        let textView = IntrinsicTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.font = NSFont.systemFont(ofSize: 17)
        textView.textColor = .labelColor
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.required, for: .vertical)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        return textView
    }

    func updateNSView(_ textView: IntrinsicTextView, context: Context) {
        if textView.string != text {
            textView.string = text
        }
        textView.delegate = context.coordinator
        textView.invalidateIntrinsicContentSize()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let onSelection: (String?) -> Void

        init(onSelection: @escaping (String?) -> Void) {
            self.onSelection = onSelection
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard
                let textView = notification.object as? NSTextView,
                textView.selectedRange().length > 0,
                let range = Range(textView.selectedRange(), in: textView.string)
            else {
                onSelection(nil)
                return
            }

            let selectedText = String(textView.string[range])
            let trimmedText = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            onSelection(trimmedText.isEmpty ? nil : trimmedText)
        }
    }

    final class IntrinsicTextView: NSTextView {
        override var intrinsicContentSize: NSSize {
            guard let layoutManager, let textContainer else {
                return NSSize(width: NSView.noIntrinsicMetric, height: 0)
            }

            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            return NSSize(width: NSView.noIntrinsicMetric, height: ceil(usedRect.height))
        }

        override func layout() {
            super.layout()
            invalidateIntrinsicContentSize()
        }
    }
}
