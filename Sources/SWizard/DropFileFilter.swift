import Foundation

enum DropFileFilter {
    static let supportedExtensions: Set<String> = ["nsp", "nsz", "xci", "xcz"]

    static func resolveSupportedURL(fromFileURLData data: Data) -> URL? {
        guard let url = URL(dataRepresentation: data, relativeTo: nil) else {
            return nil
        }

        guard supportedExtensions.contains(url.pathExtension.lowercased()) else {
            return nil
        }

        return url
    }
}
