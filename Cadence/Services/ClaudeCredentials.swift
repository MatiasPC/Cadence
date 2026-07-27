import Foundation
import Security

/// Reads Claude Code's OAuth access token from the macOS Keychain
/// (`Claude Code-credentials`).
///
/// Keychain access to another app's item is gated by an ACL. Reading it can put
/// up a blocking system panel, so reads here are **silent by default**: we
/// disable user interaction, and a denied ACL comes back as `.needsPermission`
/// instead of a dialog. The one interactive read happens only when the user
/// explicitly asks for it from the panel, so the prompt is always a direct
/// response to something they clicked.
enum ClaudeCredentials {

    enum ReadResult: Equatable {
        /// A token was read successfully.
        case token(String)
        /// The item exists but our ACL entry doesn't grant access. An
        /// interactive read would show the system "allow access" panel.
        case needsPermission
        /// No such keychain item — Claude Code isn't logged in on this machine.
        case missing
        /// The item was read but didn't contain a token in a shape we know.
        case unreadable
    }

    /// Reads without ever showing UI. Safe to call from background polling.
    static func read() -> ReadResult {
        read(interactive: false)
    }

    /// Reads and allows the system permission panel to appear. Only call this
    /// in direct response to a user action.
    static func readInteractively() -> ReadResult {
        read(interactive: true)
    }

    private static func read(interactive: Bool) -> ReadResult {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = interactive
            ? SecItemCopyMatching(query as CFDictionary, &item)
            : withoutUserInteraction { SecItemCopyMatching(query as CFDictionary, &item) }

        switch status {
        case errSecSuccess:
            break
        case errSecItemNotFound:
            return .missing
        // A suppressed ACL panel surfaces as either of these depending on how
        // the item was written; both mean "the user has to approve this".
        case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled:
            return .needsPermission
        default:
            return .needsPermission
        }

        guard let data = item as? Data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .unreadable }

        // Stored as {"claudeAiOauth": {"accessToken": ...}}; tolerate a flat shape too.
        let oauth = (root["claudeAiOauth"] as? [String: Any]) ?? root
        guard let token = oauth["accessToken"] as? String, !token.isEmpty else {
            return .unreadable
        }
        return .token(token)
    }

    // MARK: - Legacy interaction suppression

    /// Runs `body` with the process-wide Keychain prompt suppressed.
    ///
    /// `SecKeychain*` is deprecated with no replacement that covers this case.
    /// The item lives in the login keychain behind a classic ACL, and a denied
    /// read raises the old SecKeychain panel — `kSecUseAuthenticationUI` does
    /// not suppress *that* panel, and the LAContext API Apple points to governs
    /// biometric/passcode prompts instead. So this call is load-bearing: it is
    /// the only thing standing between a background poll and a modal dialog.
    /// The deprecation warning here is expected and intentional.
    private static func withoutUserInteraction(_ body: () -> OSStatus) -> OSStatus {
        SecKeychainSetUserInteractionAllowed(false)
        defer { SecKeychainSetUserInteractionAllowed(true) }
        return body()
    }
}
