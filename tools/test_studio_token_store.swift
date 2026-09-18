// Where the OAuth tokens actually land.
//
// §6.1: "Tokens live in the Keychain, …AfterFirstUnlockThisDeviceOnly, never
// synchronised, never logged, never written to disk in plaintext. The stream
// key rule (§5) applies to tokens too."
//
// No token has ever existed, so none of that has ever been observed. It is
// about to matter: both client ids are registered, the next thing the owner
// does is sign in, and Twitch's refresh tokens are ONE-TIME-USE — a token that
// fails to store is not an inconvenience, it is a host who is silently signed
// out with no way to tell why.
//
// Two questions this asks of the real API on this real machine:
//
//   1. Does `save` actually save — and would it TELL anyone if it did not?
//   2. Does `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` mean anything
//      on macOS? On macOS a generic password goes to the FILE-BASED keychain
//      unless `kSecUseDataProtectionKeychain` is set, and the file-based
//      keychain has no concept of `kSecAttrAccessible` at all.
//
//   swiftc -parse-as-library \
//     ArchiveWatch/ArchiveWatch/Studio/StudioPlatformAuth.swift \
//     ArchiveWatch/ArchiveWatch/Studio/StudioPlatforms.swift \
//     tools/test_studio_token_store.swift -o /tmp/aw_tokens && /tmp/aw_tokens
//
// It writes ONLY under a probe account name and deletes it again, so it can
// never disturb a real sign-in.

import Foundation
import Security

@main
struct TokenStoreProbe {
    static let probe = "harness-probe-do-not-use"
    static let service = "org.archivewatch.studio.oauth"
    static var failures: [String] = []

    static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        print(ok ? "  PASS  \(name)" : "  FAIL  \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        if !ok { failures.append(name) }
    }

    /// The item's attributes as the Keychain itself reports them — the only
    /// witness that does not depend on what we believe we asked for.
    static func attributes(dataProtection: Bool) -> [String: Any]? {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: probe,
                                kSecReturnAttributes as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        if dataProtection { q[kSecUseDataProtectionKeychain as String] = true }
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? [String: Any]
    }

    static func main() {
        print("Watch Together — where the tokens land\n")

        StudioTokenStore.clear(for: probe)
        check("CONTROL — nothing is stored before the test writes",
              StudioTokenStore.load(for: probe) == nil,
              "a previous run left an item behind")

        let token = StudioTokenStore.Token(access: "probe-access",
                                           refresh: "probe-refresh",
                                           expires: Date().addingTimeInterval(3600))
        StudioTokenStore.save(token, for: probe)

        let back = StudioTokenStore.load(for: probe)
        check("save then load round-trips the token", back?.access == "probe-access",
              back == nil ? "nothing came back" : "wrong value")
        check("...and the refresh token survives, which is what Twitch cannot re-issue",
              back?.refresh == "probe-refresh")

        // Q2: which keychain did it land in?
        let legacy = attributes(dataProtection: false)
        let dataProt = attributes(dataProtection: true)
        print("\n  the item is readable from:")
        print("    the file-based (legacy) keychain: \(legacy != nil)")
        print("    the data-protection keychain:     \(dataProt != nil)")

        // `kSecAttrAccessible` is meaningful ONLY in the data-protection
        // keychain. If the item lives in the legacy one, the accessibility we
        // asked for was accepted by the API and then ignored.
        let acc = (dataProt?[kSecAttrAccessible as String] ?? legacy?[kSecAttrAccessible as String]) as? String
        print("    kSecAttrAccessible reported:      \(acc ?? "<absent>")")

        // WHAT THIS HARNESS CANNOT DECIDE, said plainly.
        //
        // Reaching the data-protection keychain needs an entitlement, and a
        // bare command-line binary has none: a direct probe answers
        // `-34018, a required entitlement is not present`. So the result above
        // describes THIS process, not the signed app — an unentitled process
        // would land in the file-based keychain even if the product were
        // perfect. Asserting "the token is in the data-protection keychain"
        // here would be an assertion that can never pass, which is worse than
        // no assertion at all.
        //
        // The measurement that WOULD settle it has to run inside the shipping
        // app. Until then this reports and refuses to judge.
        //
        // SETTLED 2026-09-18 (§9.aaaa), and the refusal was right: run inside
        // the signed, sandboxed Mac app (`AW_KEYCHAIN_PROBE=1`), the answer was
        // that the token went to the FILE-BASED keychain and
        // `kSecAttrAccessible` came back `<absent>` — the attribute was
        // accepted by the API and meant nothing. `kSecUseDataProtectionKeychain`
        // is now set on every query and the same probe reports `cku`
        // (AfterFirstUnlockThisDeviceOnly) with `synchronizable 0`. Had this
        // harness asserted membership from out here, it would have failed
        // forever on its own lack of entitlement and told us nothing about the
        // product.
        var probeAdd: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                       kSecAttrService as String: service,
                                       kSecAttrAccount as String: probe + "-dp",
                                       kSecUseDataProtectionKeychain as String: true,
                                       kSecValueData as String: Data("x".utf8)]
        probeAdd[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let dpStatus = SecItemAdd(probeAdd as CFDictionary, nil)
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrService as String: service,
                       kSecAttrAccount as String: probe + "-dp",
                       kSecUseDataProtectionKeychain as String: true] as CFDictionary)
        print("\n  can THIS process use the data-protection keychain?")
        print("    SecItemAdd(kSecUseDataProtectionKeychain: true) -> OSStatus \(dpStatus)")
        check("CONTROL — the harness KNOWS whether it could judge the keychain choice",
              dpStatus == errSecSuccess || dpStatus == -34018,
              "unexpected status \(dpStatus) — the limitation is not what was assumed")
        if dpStatus == -34018 {
            print("    -> unentitled: the keychain-choice question is OPEN and must be")
            print("       answered inside the signed app, not here (§9.rrr).")
        }

        StudioTokenStore.clear(for: probe)
        check("clear() removes it", StudioTokenStore.load(for: probe) == nil)

        print()
        if failures.isEmpty { print("ALL CHECKS PASSED"); exit(0) }
        print("FAILED: \(failures.joined(separator: ", "))")
        exit(1)
    }
}
