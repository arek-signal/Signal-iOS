//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit
import SignalUI

// Coincides with Android's max text message length
let kMaxMessageBodyCharacterCount = 2000

protocol StoryReplyInputToolbarDelegate: AnyObject {
    func storyReplyInputToolbarDidTapSend(_ storyReplyInputToolbar: StoryReplyInputToolbar)
    func storyReplyInputToolbarDidTapReact(_ storyReplyInputToolbar: StoryReplyInputToolbar)
    func storyReplyInputToolbarDidBeginEditing(_ storyReplyInputToolbar: StoryReplyInputToolbar)
    func storyReplyInputToolbarHeightDidChange(_ storyReplyInputToolbar: StoryReplyInputToolbar)
    func storyReplyInputToolbarMentionPickerPossibleAddresses(_ storyReplyInputToolbar: StoryReplyInputToolbar) -> [SignalServiceAddress]
}

// MARK: -

class StoryReplyInputToolbar: UIView {

    weak var delegate: StoryReplyInputToolbarDelegate?

    var messageBody: MessageBody? {
        get { textView.messageBody }
        set {
            textView.messageBody = newValue
            updateContent()
        }
    }

    override var bounds: CGRect {
        didSet {
            guard oldValue.height != bounds.height else { return }
            delegate?.storyReplyInputToolbarHeightDidChange(self)
        }
    }

    let minTextViewHeight: CGFloat = 36
    var maxTextViewHeight: CGFloat {
        // About ~4 lines in portrait and ~3 lines in landscape.
        // Otherwise we risk obscuring too much of the content.
        return UIDevice.current.orientation.isPortrait ? 160 : 100
    }
    var textViewHeightConstraint: NSLayoutConstraint?

    // MARK: - Initializers

    init() {
        super.init(frame: CGRect.zero)

        // When presenting or dismissing the keyboard, there may be a slight
        // gap between the keyboard and the bottom of the input bar during
        // the animation. Extend the background below the toolbar's bounds
        // by this much to mask that extra space.
        let backgroundExtension: CGFloat = 500

        if UIAccessibility.isReduceTransparencyEnabled {
            self.backgroundColor = .ows_black

            let extendedBackground = UIView()
            addSubview(extendedBackground)
            extendedBackground.autoPinWidthToSuperview()
            extendedBackground.autoPinEdge(.top, to: .bottom, of: self)
            extendedBackground.autoSetDimension(.height, toSize: backgroundExtension)
        } else {
            self.backgroundColor = .clear

            let blurEffectView = UIVisualEffectView(effect: Theme.darkThemeBarBlurEffect)
            blurEffectView.layer.zPosition = -1
            addSubview(blurEffectView)
            blurEffectView.autoPinWidthToSuperview()
            blurEffectView.autoPinEdge(toSuperviewEdge: .top)
            blurEffectView.autoPinEdge(toSuperviewEdge: .bottom, withInset: -backgroundExtension)
        }

        textView.mentionDelegate = self

        let sendButton = OWSButton.sendButton(imageName: "send-solid-24") { [weak self] in
            self?.didTapSend()
        }
        sendButtonContainer.addSubview(sendButton)

        let reactButton = OWSButton(imageName: "add-reaction-outline-24", tintColor: Theme.darkThemePrimaryColor) { [weak self] in
            self?.didTapReact()
        }
        reactButton.autoSetDimensions(to: CGSize(square: 40))
        reactButtonContainer.addSubview(reactButton)

        for button in [sendButton, reactButton] {
            button.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .top)
            button.autoPinEdge(toSuperviewEdge: .top, withInset: 0, relation: .greaterThanOrEqual)
            NSLayoutConstraint.autoSetPriority(.defaultLow) {
                button.autoPinEdge(toSuperviewEdge: .top)
            }

            button.setContentHuggingHigh()
            button.setCompressionResistanceHigh()
        }

        // The input toolbar should *always* be laid out left-to-right, even when using
        // a right-to-left language. The convention for messaging apps is for the send
        // button to always be to the right of the input field, even in RTL layouts.
        // This means, in most places you'll want to pin deliberately to left/right
        // instead of leading/trailing. You'll also want to the semanticContentAttribute
        // to ensure horizontal stack views layout left-to-right.

        let hStackView = UIStackView(arrangedSubviews: [ textContainer, sendButtonContainer, reactButtonContainer ])
        hStackView.isLayoutMarginsRelativeArrangement = true
        hStackView.layoutMargins = UIEdgeInsets(margin: 12)
        hStackView.axis = .horizontal
        hStackView.alignment = .bottom
        hStackView.spacing = 12
        hStackView.semanticContentAttribute = .forceLeftToRight

        addSubview(hStackView)
        hStackView.autoPinEdgesToSuperviewEdges()

        textViewHeightConstraint = textView.autoSetDimension(.height, toSize: minTextViewHeight)

        textContainer.autoPinEdge(toSuperviewMargin: .top)
        textContainer.autoPinEdge(toSuperviewMargin: .bottom)

        updateContent()
    }

    required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    // MARK: - UIView Overrides

    override var intrinsicContentSize: CGSize {
        get {
            // Since we have `self.autoresizingMask = UIViewAutoresizingFlexibleHeight`, we must specify
            // an intrinsicContentSize. Specifying CGSize.zero causes the height to be determined by autolayout.
            return CGSize.zero
        }
    }

    // MARK: - Subviews

    private lazy var sendButtonContainer = UIView()
    private lazy var reactButtonContainer = UIView()

    lazy var textView: MentionTextView = {
        let textView = buildTextView()

        textView.scrollIndicatorInsets = UIEdgeInsets(top: 5, left: 0, bottom: 5, right: 3)
        textView.mentionDelegate = self

        return textView
    }()

    private let placeholderText = OWSLocalizedString(
        "STORY_REPLY_TEXT_FIELD_PLACEHOLDER",
        comment: "placeholder text for replying to a story"
    )

    private lazy var placeholderTextView: UITextView = {
        let placeholderTextView = buildTextView()

        placeholderTextView.text = placeholderText
        placeholderTextView.isEditable = false
        placeholderTextView.textContainer.maximumNumberOfLines = 1
        placeholderTextView.textContainer.lineBreakMode = .byTruncatingTail
        placeholderTextView.textColor = .ows_whiteAlpha60

        return placeholderTextView
    }()

    private lazy var textContainer: UIView = {
        let textContainer = UIView()
        let textBubble = UIView()
        textContainer.addSubview(textBubble)
        let inset = (40 - minTextViewHeight) / 2
        textBubble.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: 0, leading: 0, bottom: inset, trailing: 0))

        textBubble.layer.cornerRadius = minTextViewHeight / 2
        textBubble.clipsToBounds = true
        textBubble.backgroundColor = .ows_gray75

        textBubble.addSubview(placeholderTextView)
        placeholderTextView.autoPinEdgesToSuperviewEdges()

        textBubble.addSubview(textView)
        textView.autoPinEdgesToSuperviewEdges()

        return textContainer
    }()

    private func buildTextView() -> MentionTextView {
        let textView = MentionTextView()

        textView.keyboardAppearance = Theme.darkThemeKeyboardAppearance
        textView.backgroundColor = .clear
        textView.tintColor = Theme.darkThemePrimaryColor

        let textViewFont = UIFont.ows_dynamicTypeBody
        textView.font = textViewFont
        textView.textColor = Theme.darkThemePrimaryColor

        // Check the system font size and increase text inset accordingly
        // to keep the text vertically centered
        textView.updateVerticalInsetsForDynamicBodyType(defaultInsets: 7)
        textView.textContainerInset.left = 7
        textView.textContainerInset.right = 7

        return textView
    }

    // MARK: - Actions

    func didTapSend() {
        textView.acceptAutocorrectSuggestion()
        delegate?.storyReplyInputToolbarDidTapSend(self)
    }

    func didTapReact() {
        delegate?.storyReplyInputToolbarDidTapReact(self)
    }

    // MARK: - Helpers

    private func updateContent() {
        AssertIsOnMainThread()

        updateHeight(textView: textView)

        let isTextViewEmpty = textView.text.isEmptyOrNil

        reactButtonContainer.isHidden = !isTextViewEmpty
        sendButtonContainer.isHidden = isTextViewEmpty
        placeholderTextView.isHidden = !isTextViewEmpty
    }

    private func updateHeight(textView: UITextView) {
        guard let textViewHeightConstraint = textViewHeightConstraint else {
            owsFailDebug("Missing constraint.")
            return
        }

        // compute new height assuming width is unchanged
        let currentSize = textView.frame.size
        let textViewHeight = clampedTextViewHeight(fixedWidth: currentSize.width)

        if textViewHeightConstraint.constant != textViewHeight {
            Logger.debug("TextView height changed: \(textViewHeightConstraint.constant) -> \(textViewHeight)")
            textViewHeightConstraint.constant = textViewHeight
            invalidateIntrinsicContentSize()
        }
    }

    private func clampedTextViewHeight(fixedWidth: CGFloat) -> CGFloat {
        let contentSize = textView.sizeThatFits(CGSize(width: fixedWidth, height: CGFloat.greatestFiniteMagnitude))
        return CGFloatClamp(contentSize.height, minTextViewHeight, maxTextViewHeight)
    }
}

extension StoryReplyInputToolbar: MentionTextViewDelegate {
    func textViewDidBeginTypingMention(_ textView: MentionTextView) {}

    func textViewDidEndTypingMention(_ textView: MentionTextView) {}

    func textViewMentionPickerParentView(_ textView: MentionTextView) -> UIView? {
        return superview
    }

    func textViewMentionPickerReferenceView(_ textView: MentionTextView) -> UIView? {
        return self
    }

    func textViewMentionPickerPossibleAddresses(_ textView: MentionTextView) -> [SignalServiceAddress] {
        return delegate?.storyReplyInputToolbarMentionPickerPossibleAddresses(self) ?? []
    }

    func textView(_ textView: MentionTextView, didDeleteMention mention: Mention) {}

    func textView(_ textView: MentionTextView, shouldResolveMentionForAddress address: SignalServiceAddress) -> Bool {
        return textViewMentionPickerPossibleAddresses(textView).contains(address)
    }

    func textViewMentionStyle(_ textView: MentionTextView) -> Mention.Style {
        return .groupReply
    }

    public func textViewDidChange(_ textView: UITextView) {
        updateHeight(textView: textView)
        updateContent()
    }

    public func textViewDidBeginEditing(_ textView: UITextView) {
        delegate?.storyReplyInputToolbarDidBeginEditing(self)
        updateContent()
    }

    public func textViewDidEndEditing(_ textView: UITextView) {
        updateContent()
    }
}
