import Foundation

struct SafariCookieImportResult {
    let cookie: String?
    let failureReason: String?
}

final class SafariCookieImporter {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func roblosecurityCookie() -> SafariCookieImportResult {
        var sawPermissionError = false
        var sawCookieFile = false

        for url in safariCookieURLs() {
            guard fileManager.fileExists(atPath: url.path) else {
                continue
            }

            sawCookieFile = true

            do {
                let data = try Data(contentsOf: url)
                if let cookie = BinaryCookieParser(data: data).roblosecurityCookie() {
                    return SafariCookieImportResult(cookie: cookie, failureReason: nil)
                }
            } catch CocoaError.fileReadNoPermission, CocoaError.fileReadNoSuchFile {
                sawPermissionError = true
            } catch {
                if (error as NSError).code == NSFileReadNoPermissionError {
                    sawPermissionError = true
                }
            }
        }

        if sawPermissionError {
            return SafariCookieImportResult(
                cookie: nil,
                failureReason: "Safari session blocked by macOS privacy permissions"
            )
        }

        if sawCookieFile {
            return SafariCookieImportResult(cookie: nil, failureReason: "No Roblox session found in Safari")
        }

        return SafariCookieImportResult(cookie: nil, failureReason: "No Safari cookie store found")
    }

    private func safariCookieURLs() -> [URL] {
        let home = fileManager.homeDirectoryForCurrentUser
        return [
            home
                .appendingPathComponent("Library")
                .appendingPathComponent("Containers")
                .appendingPathComponent("com.apple.Safari")
                .appendingPathComponent("Data")
                .appendingPathComponent("Library")
                .appendingPathComponent("Cookies")
                .appendingPathComponent("Cookies.binarycookies"),
            home
                .appendingPathComponent("Library")
                .appendingPathComponent("Containers")
                .appendingPathComponent("com.apple.Safari")
                .appendingPathComponent("Data")
                .appendingPathComponent("Library")
                .appendingPathComponent("WebKit")
                .appendingPathComponent("WebsiteData")
                .appendingPathComponent("Cookies")
                .appendingPathComponent("Cookies.binarycookies"),
            home
                .appendingPathComponent("Library")
                .appendingPathComponent("Cookies")
                .appendingPathComponent("Cookies.binarycookies"),
        ]
    }
}

private struct BinaryCookieParser {
    private let data: Data

    init(data: Data) {
        self.data = data
    }

    func roblosecurityCookie() -> String? {
        guard data.count >= 8,
              String(data: data.prefix(4), encoding: .ascii) == "cook" else {
            return nil
        }

        let pageCount = Int(readUInt32BE(at: 4))
        guard pageCount > 0 else {
            return nil
        }

        let pageSizesOffset = 8
        let pageDataOffset = pageSizesOffset + pageCount * 4
        guard data.count >= pageDataOffset else {
            return nil
        }

        var pageSizes: [Int] = []
        for index in 0..<pageCount {
            let size = Int(readUInt32BE(at: pageSizesOffset + index * 4))
            guard size > 0 else {
                return nil
            }
            pageSizes.append(size)
        }

        var pageOffset = pageDataOffset
        for pageSize in pageSizes {
            guard pageOffset + pageSize <= data.count else {
                return nil
            }

            if let cookie = parsePage(offset: pageOffset, length: pageSize) {
                return cookie
            }

            pageOffset += pageSize
        }

        return nil
    }

    private func parsePage(offset: Int, length: Int) -> String? {
        guard length >= 8 else {
            return nil
        }

        let cookieCount = Int(readUInt32LE(at: offset + 4))
        guard cookieCount > 0 else {
            return nil
        }

        let offsetsStart = offset + 8
        guard offsetsStart + cookieCount * 4 <= offset + length else {
            return nil
        }

        for index in 0..<cookieCount {
            let cookieRelativeOffset = Int(readUInt32LE(at: offsetsStart + index * 4))
            let cookieOffset = offset + cookieRelativeOffset
            guard cookieOffset >= offset,
                  cookieOffset + 52 <= offset + length else {
                continue
            }

            if let cookie = parseCookie(offset: cookieOffset, pageEnd: offset + length) {
                return cookie
            }
        }

        return nil
    }

    private func parseCookie(offset: Int, pageEnd: Int) -> String? {
        let size = Int(readUInt32LE(at: offset))
        guard size >= 52,
              offset + size <= pageEnd else {
            return nil
        }

        let urlOffset = Int(readUInt32LE(at: offset + 16))
        let nameOffset = Int(readUInt32LE(at: offset + 20))
        let valueOffset = Int(readUInt32LE(at: offset + 28))

        guard let domain = nullTerminatedString(at: offset + urlOffset, max: offset + size),
              let name = nullTerminatedString(at: offset + nameOffset, max: offset + size),
              let value = nullTerminatedString(at: offset + valueOffset, max: offset + size) else {
            return nil
        }

        guard domain.contains("roblox.com"),
              name == ".ROBLOSECURITY",
              !value.isEmpty else {
            return nil
        }

        return value
    }

    private func nullTerminatedString(at offset: Int, max end: Int) -> String? {
        guard offset >= 0,
              offset < end,
              end <= data.count else {
            return nil
        }

        var cursor = offset
        while cursor < end, data[cursor] != 0 {
            cursor += 1
        }

        guard cursor > offset else {
            return nil
        }

        return String(data: data[offset..<cursor], encoding: .utf8)
    }

    private func readUInt32BE(at offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else {
            return 0
        }

        return data[offset..<offset + 4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    private func readUInt32LE(at offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else {
            return 0
        }

        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
