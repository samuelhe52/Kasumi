import Foundation

/// Returns the fragment when `url` points into the current document: a bare `#fragment`,
/// or a file URL with the same path, host, port, credentials, and query. A relative
/// link such as `chapter.md#intro` returns nil, so it goes to the host.
func readerDocumentFragment(in url: URL, documentURL: URL?) -> String? {
    guard let fragment = url.fragment else { return nil }
    if url.absoluteString.hasPrefix("#") { return fragment }
    guard url.isFileURL, let documentURL, documentURL.isFileURL,
        let target = URLComponents(url: url, resolvingAgainstBaseURL: true),
        let document = URLComponents(url: documentURL, resolvingAgainstBaseURL: true),
        target.user == document.user, target.password == document.password, target.port == document.port,
        fileHost(target.host) == fileHost(document.host), target.percentEncodedQuery == document.percentEncodedQuery,
        url.standardizedFileURL.path == documentURL.standardizedFileURL.path
    else { return nil }
    return fragment
}

private func fileHost(_ host: String?) -> String {
    let host = host?.lowercased() ?? ""
    return host == "localhost" ? "" : host
}
