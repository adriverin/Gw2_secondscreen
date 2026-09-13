import CryptoKit
import Foundation
import UIKit

actor CharacterPortraitStore {
    static let shared = CharacterPortraitStore()
    private let directory: URL

    init(directory: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.directory = directory ?? support.appending(path: "CharacterPortraits", directoryHint: .isDirectory)
    }

    func data(account: String?, character: String) -> Data? {
        try? Data(contentsOf: url(account: account, character: character))
    }

    func save(_ data: Data, account: String?, character: String) throws {
        guard let image = UIImage(data: data) else { return }
        let maxDimension: CGFloat = 1_600
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let encoded = resized.jpegData(compressionQuality: 0.86) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoded.write(to: url(account: account, character: character), options: .atomic)
    }

    func remove(account: String?, character: String) throws {
        let file = url(account: account, character: character)
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }

    private func url(account: String?, character: String) -> URL {
        let value = "\(account ?? "local")|\(character)"
        let name = SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: name).appendingPathExtension("jpg")
    }
}
