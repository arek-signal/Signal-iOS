//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class ComposeViewController: OWSViewController {
    let recipientPicker = RecipientPickerViewController()

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("MESSAGE_COMPOSEVIEW_TITLE", comment: "Title for the compose view.")

        view.backgroundColor = Theme.backgroundColor

        recipientPicker.allowsSelectingUnregisteredPhoneNumbers = false
        recipientPicker.shouldShowInvites = true
        recipientPicker.shouldShowNewGroup = true
        recipientPicker.shouldHideLocalRecipient = false
        recipientPicker.delegate = self
        addChild(recipientPicker)
        view.addSubview(recipientPicker.view)
        recipientPicker.view.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        recipientPicker.view.autoPinEdge(toSuperviewEdge: .leading)
        recipientPicker.view.autoPinEdge(toSuperviewEdge: .trailing)
        recipientPicker.view.autoPinEdge(toSuperviewEdge: .bottom)

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(dismissPressed))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        recipientPicker.applyTheme(to: self)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        recipientPicker.removeTheme(from: self)
    }

    @objc func dismissPressed() {
        dismiss(animated: true)
    }

    @objc func newGroupPressed() {
        showNewGroupUI()
    }

    func newConversation(address: SignalServiceAddress) {
        AssertIsOnMainThread()
        owsAssertDebug(address.isValid)

        let thread = Self.databaseStorage.write { transaction in
            TSContactThread.getOrCreateThread(withContactAddress: address,
                                              transaction: transaction)
        }
        self.newConversation(thread: thread)
    }

    func newConversation(thread: TSThread) {
        SignalApp.shared().presentConversation(for: thread, action: .compose, animated: false)
        presentingViewController?.dismiss(animated: true)
    }

    func showNewGroupUI() {
        navigationController?.pushViewController(NewGroupMembersViewController(), animated: true)
    }
}

extension ComposeViewController: RecipientPickerDelegate {

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        canSelectRecipient recipient: PickedRecipient
    ) -> RecipientPickerRecipientState {
        return .canBeSelected
    }

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        didSelectRecipient recipient: PickedRecipient
    ) {
        switch recipient.identifier {
        case .address(let address):
            newConversation(address: address)
        case .group(let groupThread):
            newConversation(thread: groupThread)
        }
    }

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         willRenderRecipient recipient: PickedRecipient) {
        // Do nothing.
    }

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         prepareToSelectRecipient recipient: PickedRecipient) -> AnyPromise {
        owsFailDebug("This method should not called.")
        return AnyPromise(Promise.value(()))
    }

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         showInvalidRecipientAlert recipient: PickedRecipient) {
        owsFailDebug("Unexpected error.")
    }

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        didDeselectRecipient recipient: PickedRecipient
    ) {}

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        accessoryMessageForRecipient recipient: PickedRecipient,
        transaction: SDSAnyReadTransaction
    ) -> String? {
        switch recipient.identifier {
        case .address(let address):
            guard blockingManager.isAddressBlocked(address, transaction: transaction) else { return nil }
            return MessageStrings.conversationIsBlocked
        case .group(let thread):
            guard blockingManager.isThreadBlocked(thread, transaction: transaction) else { return nil }
            return MessageStrings.conversationIsBlocked
        }
    }

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         attributedSubtitleForRecipient recipient: PickedRecipient,
                         transaction: SDSAnyReadTransaction) -> NSAttributedString? {
        switch recipient.identifier {
        case .address(let address):
            guard !address.isLocalAddress else {
                return nil
            }
            if let bioForDisplay = Self.profileManagerImpl.profileBioForDisplay(for: address,
                                                                                transaction: transaction) {
                return NSAttributedString(string: bioForDisplay)
            }
            return nil
        case .group:
            return nil
        }
    }

    func recipientPickerTableViewWillBeginDragging(_ recipientPickerViewController: RecipientPickerViewController) {}

    func recipientPickerNewGroupButtonWasPressed() {
        showNewGroupUI()
    }

    func recipientPickerCustomHeaderViews() -> [UIView] { return [] }
}
