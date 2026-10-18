import Foundation

/// The PSN account id the PS5 wants at pairing: the numeric user id as 8 little-endian bytes, base64.
/// Obtained like chiaki-ng's scripts/psn-account-id.py: the user logs in to Sony in a browser, the
/// redirect URL carries a `code`, and two HTTPS calls turn it into the user id. These OAuth client
/// values are the Remote Play client's, as published in the chiaki-ng repository.
enum PSNAccountID {
    private static let clientID = "ba495a24-818c-472b-b12d-ff231c1b5745"
    private static let clientSecret = "mvaiZkRsAsI1IBkY"
    static let redirectURI = "https://remoteplay.dl.playstation.net/remoteplay/redirect"
    private static let tokenURL = URL(string: "https://auth.api.sonyentertainmentnetwork.com/2.0/oauth/token")!

    static var loginURL: URL {
        var components = URLComponents(string: "https://auth.api.sonyentertainmentnetwork.com/2.0/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "service_entity", value: "urn:service-entity:psn"),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "psn:clientapp"),
            URLQueryItem(name: "request_locale", value: "pt_BR"),
            URLQueryItem(name: "ui", value: "pr"),
            URLQueryItem(name: "service_logo", value: "ps"),
            URLQueryItem(name: "layout_type", value: "popup"),
            URLQueryItem(name: "smcid", value: "remoteplay"),
            URLQueryItem(name: "prompt", value: "always"),
            URLQueryItem(name: "PlatformPrivacyWs1", value: "minimal"),
        ]
        return components.url!
    }

    enum Failure: Error, CustomStringConvertible {
        case noCode
        case http(Int, String)
        case malformed(String)

        var description: String {
            switch self {
            case .noCode: return "a URL colada não tem o parâmetro \"code\""
            case .http(let status, let body): return "a Sony respondeu HTTP \(status): \(body.prefix(300))"
            case .malformed(let what): return "resposta inesperada da Sony: \(what)"
            }
        }
    }

    /// The `code` query parameter of the redirect URL the browser lands on after login.
    static func code(fromRedirectURL text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed) else { return nil }
        return components.queryItems?.first(where: { $0.name == "code" })?.value.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Exchanges the code for the account id (base64). Network call.
    static func fetchAccountID(code: String) async throws -> String {
        let credentials = Data("\(clientID):\(clientSecret)".utf8).base64EncodedString()

        var tokenRequest = URLRequest(url: tokenURL)
        tokenRequest.httpMethod = "POST"
        tokenRequest.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        tokenRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        tokenRequest.httpBody = Data("grant_type=authorization_code&code=\(code)&redirect_uri=\(redirectURI)&".utf8)
        let tokenJSON = try await json(for: tokenRequest)
        guard let token = tokenJSON["access_token"] as? String else {
            throw Failure.malformed("sem access_token")
        }

        let escaped = token.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? token
        var accountRequest = URLRequest(url: tokenURL.appendingPathComponent(escaped))
        accountRequest.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        let accountJSON = try await json(for: accountRequest)
        guard let userIDText = accountJSON["user_id"] as? String, let userID = UInt64(userIDText) else {
            throw Failure.malformed("sem user_id numérico")
        }
        return encode(userID: userID)
    }

    static func encode(userID: UInt64) -> String {
        var little = userID.littleEndian
        return withUnsafeBytes(of: &little) { Data($0).base64EncodedString() }
    }

    /// The 8 bytes behind a base64 account id, or nil when it is not one.
    static func decode(_ base64: String) -> [UInt8]? {
        guard let data = Data(base64Encoded: base64.trimmingCharacters(in: .whitespacesAndNewlines)), data.count == 8 else {
            return nil
        }
        return Array(data)
    }

    private static func json(for request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw Failure.http(status, String(decoding: data, as: UTF8.self))
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.malformed("corpo não é um objeto JSON")
        }
        return object
    }
}
