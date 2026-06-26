import CommonCrypto
import Foundation
import SQLite3
import Security

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct ChromeCookieImportResult {
    let cookie: String?
    let failureReason: String?
}

final class ChromeCookieImporter {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func roblosecurityCookie() -> ChromeCookieImportResult {
        let cookieURLs = chromeCookieURLs()
        guard !cookieURLs.isEmpty else {
            return ChromeCookieImportResult(cookie: nil, failureReason: "No Chrome cookie store found")
        }

        guard let chromePassword = chromeSafeStoragePassword() else {
            return ChromeCookieImportResult(cookie: nil, failureReason: "Chrome Safe Storage password unavailable")
        }

        var sawRobloxCookie = false
        var sawUnreadableStore = false
        var sawUndecryptableCookie = false

        for url in cookieURLs {
            switch roblosecurityCookie(from: url, chromePassword: chromePassword) {
            case .success(let cookie):
                return ChromeCookieImportResult(cookie: cookie, failureReason: nil)
            case .notFound:
                continue
            case .unreadable:
                sawUnreadableStore = true
            case .undecryptable:
                sawRobloxCookie = true
                sawUndecryptableCookie = true
            }
        }

        if sawUndecryptableCookie || sawRobloxCookie {
            return ChromeCookieImportResult(cookie: nil, failureReason: "Chrome Roblox session could not be decrypted")
        }

        if sawUnreadableStore {
            return ChromeCookieImportResult(cookie: nil, failureReason: "Chrome cookie store could not be read")
        }

        return ChromeCookieImportResult(cookie: nil, failureReason: "No Roblox session found in Chrome")
    }

    private func chromeCookieURLs() -> [URL] {
        let chromeRoot = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Google")
            .appendingPathComponent("Chrome")

        var candidates = [
            chromeRoot.appendingPathComponent("Default").appendingPathComponent("Cookies"),
            chromeRoot.appendingPathComponent("Default").appendingPathComponent("Network").appendingPathComponent("Cookies"),
        ]

        if let profileNames = try? fileManager.contentsOfDirectory(atPath: chromeRoot.path) {
            for profileName in profileNames where profileName == "Guest Profile" || profileName.hasPrefix("Profile ") {
                let profileURL = chromeRoot.appendingPathComponent(profileName)
                candidates.append(profileURL.appendingPathComponent("Cookies"))
                candidates.append(profileURL.appendingPathComponent("Network").appendingPathComponent("Cookies"))
                candidates.append(profileURL.appendingPathComponent("Default").appendingPathComponent("Cookies"))
                candidates.append(profileURL.appendingPathComponent("Default").appendingPathComponent("Network").appendingPathComponent("Cookies"))
            }
        }

        var seenPaths = Set<String>()
        return candidates.filter { url in
            guard fileManager.fileExists(atPath: url.path),
                  !seenPaths.contains(url.path) else {
                return false
            }

            seenPaths.insert(url.path)
            return true
        }
    }

    private func roblosecurityCookie(from url: URL, chromePassword: String) -> CookieDatabaseResult {
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK, let database else {
            if let database {
                sqlite3_close(database)
            }
            return .unreadable
        }
        defer {
            sqlite3_close(database)
        }

        let sql = """
        SELECT host_key, value, encrypted_value
        FROM cookies
        WHERE host_key LIKE ? AND name = ?
        ORDER BY expires_utc DESC
        LIMIT 5
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return .unreadable
        }
        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_text(statement, 1, "%roblox.com", -1, sqliteTransient)
        sqlite3_bind_text(statement, 2, ".ROBLOSECURITY", -1, sqliteTransient)

        var foundCookie = false
        while sqlite3_step(statement) == SQLITE_ROW {
            foundCookie = true

            guard let hostKeyPointer = sqlite3_column_text(statement, 0) else {
                continue
            }
            let hostKey = String(cString: hostKeyPointer)

            if let valuePointer = sqlite3_column_text(statement, 1) {
                let value = String(cString: valuePointer)
                if !value.isEmpty {
                    return .success(value)
                }
            }

            guard let blobPointer = sqlite3_column_blob(statement, 2) else {
                continue
            }

            let blobLength = Int(sqlite3_column_bytes(statement, 2))
            guard blobLength > 0 else {
                continue
            }

            let encryptedValue = Data(bytes: blobPointer, count: blobLength)
            if let decrypted = decryptChromeCookie(encryptedValue, chromePassword: chromePassword, hostKey: hostKey),
               !decrypted.isEmpty {
                return .success(decrypted)
            }
        }

        return foundCookie ? .undecryptable : .notFound
    }

    private func chromeSafeStoragePassword() -> String? {
        let service = "Chrome Safe Storage"
        let account = "Chrome"
        var passwordLength: UInt32 = 0
        var passwordData: UnsafeMutableRawPointer?

        let status = service.withCString { servicePointer in
            account.withCString { accountPointer in
                SecKeychainFindGenericPassword(
                    nil,
                    UInt32(strlen(servicePointer)),
                    servicePointer,
                    UInt32(strlen(accountPointer)),
                    accountPointer,
                    &passwordLength,
                    &passwordData,
                    nil
                )
            }
        }

        guard status == errSecSuccess,
              let passwordData else {
            return nil
        }
        defer {
            SecKeychainItemFreeContent(nil, passwordData)
        }

        let data = Data(bytes: passwordData, count: Int(passwordLength))
        return String(data: data, encoding: .utf8)
    }

    private func decryptChromeCookie(_ encryptedValue: Data, chromePassword: String, hostKey: String) -> String? {
        let encryptedPrefixLength = 3
        let prefixes = ["v10", "v11"]
        let encryptedText: Data

        if encryptedValue.count > encryptedPrefixLength,
           let prefix = String(data: encryptedValue.prefix(encryptedPrefixLength), encoding: .ascii),
           prefixes.contains(prefix) {
            encryptedText = encryptedValue.dropFirst(encryptedPrefixLength)
        } else {
            encryptedText = encryptedValue
        }

        guard let key = chromeEncryptionKey(password: chromePassword) else {
            return nil
        }

        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        var output = Data(repeating: 0, count: encryptedText.count + kCCBlockSizeAES128)
        var outputLength = 0
        let keyLength = key.count
        let encryptedTextLength = encryptedText.count
        let outputCapacity = output.count

        let status = key.withUnsafeBytes { keyBytes in
            iv.withUnsafeBytes { ivBytes in
                encryptedText.withUnsafeBytes { encryptedBytes in
                    output.withUnsafeMutableBytes { outputBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            keyLength,
                            ivBytes.baseAddress,
                            encryptedBytes.baseAddress,
                            encryptedTextLength,
                            outputBytes.baseAddress,
                            outputCapacity,
                            &outputLength
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else {
            return nil
        }

        output.removeSubrange(outputLength..<output.count)

        if let value = String(data: output, encoding: .utf8) {
            return value
        }

        let hostDigest = sha256(Data(hostKey.utf8))
        if output.count > hostDigest.count,
           output.prefix(hostDigest.count) == hostDigest {
            let valueData = output.dropFirst(hostDigest.count)
            return String(data: valueData, encoding: .utf8)
        }

        return nil
    }

    private func chromeEncryptionKey(password: String) -> Data? {
        let salt = Array("saltysalt".utf8)
        var key = Data(repeating: 0, count: kCCKeySizeAES128)
        let keyLength = key.count

        let status = password.withCString { passwordPointer in
            key.withUnsafeMutableBytes { keyBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordPointer,
                    strlen(passwordPointer),
                    salt,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                    1003,
                    keyBytes.bindMemory(to: UInt8.self).baseAddress,
                    keyLength
                )
            }
        }

        return status == kCCSuccess ? key : nil
    }

    private func sha256(_ data: Data) -> Data {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { dataBytes in
            _ = CC_SHA256(dataBytes.baseAddress, CC_LONG(data.count), &digest)
        }
        return Data(digest)
    }
}

private enum CookieDatabaseResult {
    case success(String)
    case notFound
    case unreadable
    case undecryptable
}
