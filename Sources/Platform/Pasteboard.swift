//  Pasteboard.swift
//  Writing to the macOS pasteboard, with a Value marked so the rest of the system
//  leaves it alone.
//
//  A copied Value is plaintext on a surface Janitor does not own. Three markers narrow
//  what happens to it next. None of them is enforced by the operating system.
//
//  - `org.nspasteboard.ConcealedType` means "this is a password, do not record it". It
//    is a convention rather than an API, and the widely used clipboard managers honor
//    it.
//  - `org.nspasteboard.TransientType` means "do not store this at all". Same
//    convention, same standing.
//  - `com.apple.is-sensitive` is what keeps an item off Universal Clipboard, so it does
//    not reach the operator's other devices. Apple does not document it. It is included
//    because it is the only lever there is, and it costs an empty data item.
//
//  A clipboard manager that ignores the conventions still records the Value. These are
//  the strongest controls the platform offers, not a guarantee.
//
//  `clearIfOwned` is the fourth control. It clears the pasteboard only while Janitor
//  still owns the contents, so a Value that aged out is removed without wiping
//  something the operator copied in the meantime.

import AppKit

@MainActor
enum Pasteboard {
    private static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    private static let sensitive = NSPasteboard.PasteboardType("com.apple.is-sensitive")

    /// The change count of the last Value Janitor wrote, so a later clear can tell
    /// whether the contents are still ours.
    private static var ownedChangeCount: Int?

    /// Copy metadata — an Entry name, an environment, an ARN. Not secret, so it is
    /// written plainly and left for the operator to manage.
    static func copyPlain(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        ownedChangeCount = nil
    }

    /// Copy a revealed Value, marked concealed, transient, and sensitive.
    static func copyConcealed(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        // The markers carry no payload. Their presence is the signal.
        for marker in [concealed, transient, sensitive] {
            pasteboard.setData(Data(), forType: marker)
        }
        ownedChangeCount = pasteboard.changeCount
    }

    /// Clear the pasteboard, but only while it still holds what Janitor put there.
    static func clearIfOwned() {
        guard let owned = ownedChangeCount else { return }
        ownedChangeCount = nil
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount == owned else { return }
        pasteboard.clearContents()
    }
}
