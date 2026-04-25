import Foundation

/// Server-issued upload proof returned by POST /evidence/upload.
///
/// The client NEVER constructs this type. It is only received from the backend
/// after a successful multipart upload. Pass `uploadId` to subsequent calls
/// (e.g. POST /evidence/upload/{challenge_id}) to associate the file with a match.
struct FileUploadToken: Decodable {
    let uploadId: String
    let fileURL: String
    let mimeType: String
    let sizeBytes: Int

    enum CodingKeys: String, CodingKey {
        case uploadId  = "upload_id"
        case fileURL   = "file_url"
        case mimeType  = "mime_type"
        case sizeBytes = "size_bytes"
    }

    #if DEBUG
    /// Assert structural validity of a decoded upload token.
    /// Call immediately after receiving a FileUploadToken from the backend.
    /// Catches malformed backend responses early — before uploadId is passed to
    /// a subsequent associate call where a silent failure would be harder to trace.
    func assertValid(context: String = "") {
        let prefix = context.isEmpty ? "" : "[\(context)] "
        assert(!uploadId.isEmpty,
               "\(prefix)FileUploadToken.uploadId must not be empty — backend contract violation")
        assert(!fileURL.isEmpty,
               "\(prefix)FileUploadToken.fileURL must not be empty — backend contract violation")
        assert(fileURL.hasPrefix("http"),
               "\(prefix)FileUploadToken.fileURL '\(fileURL)' does not look like a valid URL")
        assert(sizeBytes > 0,
               "\(prefix)FileUploadToken.sizeBytes must be > 0 (got \(sizeBytes))")
        assert(!mimeType.isEmpty,
               "\(prefix)FileUploadToken.mimeType must not be empty")
    }
    #endif
}
