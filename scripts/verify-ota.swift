import CryptoKit
import Foundation

struct InvalidUpdateSignature: LocalizedError {
    var errorDescription: String? { "OTA 清单或安装包签名无效。" }
}

do {
    let arguments = CommandLine.arguments
    let feed = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
    let archive = try Data(contentsOf: URL(fileURLWithPath: arguments[2]))
    let xml = String(decoding: feed, as: UTF8.self)
    let signatureBlock = #/<!-- sparkle-signatures:\nedSignature: ([A-Za-z0-9+/=]+)\nlength: ([0-9]+)\n-->\n?\z/#
    guard let block = try signatureBlock.firstMatch(in: xml),
          let signedLength = Int(block.2), xml[..<block.range.lowerBound].utf8.count == signedLength,
          let feedSignature = Data(base64Encoded: String(block.1)),
          let archiveSignature = Data(base64Encoded: arguments[3]),
          let keyBytes = Data(base64Encoded: arguments[4]) else {
        throw InvalidUpdateSignature()
    }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyBytes)
    guard key.isValidSignature(feedSignature, for: feed.prefix(signedLength)),
          key.isValidSignature(archiveSignature, for: archive) else {
        throw InvalidUpdateSignature()
    }
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}
