//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

// Request encoding and response validation as AFNetworking 3.2 did it.
// The server parses the PHP style parameters and callers rely on non 2xx responses failing (e.g. 304 when long polling).
public enum NCHTTPSerialization {

    public enum ResponseType {
        case json
        case data
    }

    private static let methodsEncodingParametersInURI: Set<String> = ["GET", "HEAD", "DELETE"]
    private static let jsonContentTypes: Set<String> = ["application/json", "text/json", "text/javascript"]
    private static let acceptableStatusCodes = 200..<300

    // MARK: - Request

    public static func request(withMethod method: String, urlString: String, parameters: Any?, headers: [String: String], timeoutInterval: TimeInterval?) -> URLRequest? {
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = method

        if let timeoutInterval {
            request.timeoutInterval = timeoutInterval
        }

        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        let query = parameters.map { queryString(from: $0) }

        if methodsEncodingParametersInURI.contains(method.uppercased()) {
            if let query, !query.isEmpty, let urlWithQuery = URL(string: url.absoluteString + (url.query != nil ? "&" : "?") + query) {
                request.url = urlWithQuery
            }
        } else {
            // An empty string is a valid form payload, so a body is always set
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            }

            request.httpBody = (query ?? "").data(using: .utf8)
        }

        return request
    }

    public static func queryString(from parameters: Any) -> String {
        return queryStringPairs(forKey: nil, value: parameters).map { field, value in
            guard let value else { return percentEscaped(field) }
            return "\(percentEscaped(field))=\(percentEscaped(value))"
        }.joined(separator: "&")
    }

    private static func queryStringPairs(forKey key: String?, value: Any?) -> [(field: String, value: String?)] {
        guard let value = unwrapped(value) else {
            return [(key ?? "", nil)]
        }

        if let dictionary = value as? [AnyHashable: Any] {
            // Sorted, so an array of dictionaries is deserialized unambiguously
            return dictionary
                .sorted { isOrderedBefore($0.key.base, $1.key.base) }
                .flatMap { nestedKey, nestedValue in
                    let nestedKeyDescription = description(of: nestedKey.base)
                    let nestedField = key.map { "\($0)[\(nestedKeyDescription)]" } ?? nestedKeyDescription

                    return queryStringPairs(forKey: nestedField, value: nestedValue)
                }
        }

        if let array = value as? [Any] {
            return array.flatMap { queryStringPairs(forKey: "\(key ?? "")[]", value: $0) }
        }

        if let set = value as? Set<AnyHashable> {
            return set
                .sorted { isOrderedBefore($0.base, $1.base) }
                .flatMap { queryStringPairs(forKey: key, value: $0.base) }
        }

        return [(key ?? "", description(of: value))]
    }

    private static let allowedCharacters: CharacterSet = {
        // "?" and "/" stay unescaped, RFC 3986 section 3.4
        var characterSet = CharacterSet.urlQueryAllowed
        characterSet.remove(charactersIn: ":#[]@" + "!$&'()*+,;=")
        return characterSet
    }()

    static func percentEscaped(_ string: String) -> String {
        // Only fails for malformed UTF-16, sending it unescaped could inject "&" or "="
        return string.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? ""
    }

    // Matches -[NSObject description], which AFNetworking used, so bools are sent as "1" and "0"
    private static func description(of value: Any) -> String {
        if let string = value as? String {
            return string
        }

        if let bool = value as? Bool {
            return bool ? "1" : "0"
        }

        if let number = value as? NSNumber {
            return number.description
        }

        return String(describing: value)
    }

    private static func isOrderedBefore(_ lhs: Any, _ rhs: Any) -> Bool {
        return (description(of: lhs) as NSString).compare(description(of: rhs)) == .orderedAscending
    }

    // Optionals stored in an Any were bridged to NSNull by AFNetworking, which sends the field without a value
    private static func unwrapped(_ value: Any?) -> Any? {
        guard let value, !(value is NSNull) else { return nil }

        if let optional = value as? AnyOptional {
            return unwrapped(optional.wrappedValue)
        }

        return value
    }

    // MARK: - Response

    public static func responseObject(for response: URLResponse?, data: Data?, type: ResponseType) -> (responseObject: Any?, error: Error?) {
        switch type {
        case .data:
            return (data, validate(response: response, data: data, acceptableContentTypes: nil).error)
        case .json:
            return jsonResponseObject(for: response, data: data)
        }
    }

    private static func jsonResponseObject(for response: URLResponse?, data: Data?) -> (responseObject: Any?, error: Error?) {
        let (validationError, hasAcceptableContentType) = validate(response: response, data: data, acceptableContentTypes: jsonContentTypes)

        // A single space is what some servers send for an empty response
        guard hasAcceptableContentType, let data, !data.isEmpty, data != Data(" ".utf8) else {
            return (nil, validationError)
        }

        do {
            let responseObject = try JSONSerialization.jsonObject(with: data)
            return (responseObject, validationError)
        } catch {
            // On an error status the status error wins, it carries the body for OcsError
            return (nil, validationError ?? error)
        }
    }

    // An unexpected content type with an empty body is not an error, but must not be parsed either
    private static func validate(response: URLResponse?, data: Data?, acceptableContentTypes: Set<String>?) -> (error: NCHTTPResponseError?, hasAcceptableContentType: Bool) {
        guard let response = response as? HTTPURLResponse else { return (nil, true) }

        var validationError: NCHTTPResponseError?
        var hasAcceptableContentType = true
        let dataLength = data?.count ?? 0

        if let acceptableContentTypes, !acceptableContentTypes.contains(response.mimeType ?? ""), !(response.mimeType == nil && dataLength == 0) {
            if dataLength > 0 {
                validationError = NCHTTPResponseError(reason: .unacceptableContentType, response: response, data: data)
            }

            hasAcceptableContentType = false
        }

        if !acceptableStatusCodes.contains(response.statusCode) {
            validationError = NCHTTPResponseError(reason: .unacceptableStatusCode, response: response, data: data)
        }

        return (validationError, hasAcceptableContentType)
    }
}

// Lets an Optional inside an Any be recognized and unwrapped
private protocol AnyOptional {
    var wrappedValue: Any? { get }
}

extension Optional: AnyOptional {
    fileprivate var wrappedValue: Any? {
        return self.map { $0 as Any }
    }
}

public struct NCHTTPResponseError: CustomNSError, CustomStringConvertible {

    public enum Reason {
        case unacceptableStatusCode
        case unacceptableContentType
    }

    public let reason: Reason
    public let response: HTTPURLResponse
    public let data: Data?

    private var message: String {
        switch reason {
        case .unacceptableStatusCode:
            return "Request failed: \(HTTPURLResponse.localizedString(forStatusCode: response.statusCode)) (\(response.statusCode))"
        case .unacceptableContentType:
            return "Request failed: unacceptable content-type: \(response.mimeType ?? "(null)")"
        }
    }

    // Includes the start of the body, which usually holds the server's reason
    public var description: String {
        var description = "\(message), \(response.url?.absoluteString ?? "(no URL)")"

        if let data, let body = String(data: data.prefix(500), encoding: .utf8), !body.isEmpty {
            description += ", body: \(body)"
        }

        return description
    }

    // MARK: - CustomNSError

    // Standard URL error codes, so the error reads like any other networking error when bridged to NSError
    public static var errorDomain: String {
        return NSURLErrorDomain
    }

    public var errorCode: Int {
        switch reason {
        case .unacceptableStatusCode:
            return NSURLErrorBadServerResponse
        case .unacceptableContentType:
            return NSURLErrorCannotDecodeContentData
        }
    }

    public var errorUserInfo: [String: Any] {
        var userInfo: [String: Any] = [NSLocalizedDescriptionKey: message]
        userInfo[NSURLErrorFailingURLErrorKey] = response.url

        return userInfo
    }
}

public final class NCMultipartFormData {

    public let boundary = String(format: "Boundary+%08X%08X", UInt32.random(in: .min ... .max), UInt32.random(in: .min ... .max))
    private var parts: [Data] = []

    public var contentType: String {
        return "multipart/form-data; boundary=\(boundary)"
    }

    public func appendPart(withFileData data: Data, name: String, fileName: String, mimeType: String) {
        let headers = "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\nContent-Type: \(mimeType)\r\n\r\n"

        var part = Data(headers.utf8)
        part.append(data)
        parts.append(part)
    }

    public var body: Data {
        var body = Data()

        for part in parts {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(part)
            body.append(Data("\r\n".utf8))
        }

        body.append(Data("--\(boundary)--\r\n".utf8))

        return body
    }
}
