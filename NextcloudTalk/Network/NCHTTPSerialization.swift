//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

// Request encoding and response validation as AFNetworking 3.2 did it.
// The server parses the PHP style parameters and callers rely on non 2xx responses failing (e.g. 304 when long polling).
public enum NCHTTPSerialization {

    public static let errorDomain = "com.nextcloud.talk.serialization.response"
    public static let responseErrorKey = "NCHTTPSerializationResponseErrorKey"
    public static let responseDataErrorKey = "NCHTTPSerializationResponseDataErrorKey"

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

        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return value }

        return unwrapped(mirror.children.first?.value)
    }

    // MARK: - Response

    public static func responseObject(for response: URLResponse?, data: Data?, type: ResponseType) -> (responseObject: Any?, error: Error?) {
        switch type {
        case .data:
            let (_, validationError) = validate(response: response, data: data, acceptableContentTypes: nil)
            return (data, validationError)
        case .json:
            return jsonResponseObject(for: response, data: data)
        }
    }

    private static func jsonResponseObject(for response: URLResponse?, data: Data?) -> (responseObject: Any?, error: Error?) {
        let (isValid, validationError) = validate(response: response, data: data, acceptableContentTypes: jsonContentTypes)

        if !isValid, let validationError, hasCode(NSURLErrorCannotDecodeContentData, inDomain: errorDomain, error: validationError) {
            return (nil, validationError)
        }

        // A single space is what some servers send for an empty response
        guard let data, !data.isEmpty, data != Data(" ".utf8) else {
            return (nil, validationError)
        }

        do {
            let responseObject = try JSONSerialization.jsonObject(with: data)
            return (responseObject, validationError)
        } catch {
            return (nil, self.error(error as NSError, withUnderlyingError: validationError))
        }
    }

    // A response can be invalid without an error, e.g. an unexpected content type with an empty body
    private static func validate(response: URLResponse?, data: Data?, acceptableContentTypes: Set<String>?) -> (isValid: Bool, error: NSError?) {
        guard let response = response as? HTTPURLResponse else { return (true, nil) }

        var isValid = true
        var validationError: NSError?
        let dataLength = data?.count ?? 0

        if let acceptableContentTypes, !acceptableContentTypes.contains(response.mimeType ?? ""), !(response.mimeType == nil && dataLength == 0) {
            if dataLength > 0, let url = response.url {
                var userInfo: [String: Any] = [
                    NSLocalizedDescriptionKey: "Request failed: unacceptable content-type: \(response.mimeType ?? "(null)")",
                    NSURLErrorFailingURLErrorKey: url,
                    responseErrorKey: response
                ]

                userInfo[responseDataErrorKey] = data

                validationError = NSError(domain: errorDomain, code: NSURLErrorCannotDecodeContentData, userInfo: userInfo)
            }

            isValid = false
        }

        if !acceptableStatusCodes.contains(response.statusCode), let url = response.url {
            var userInfo: [String: Any] = [
                NSLocalizedDescriptionKey: "Request failed: \(HTTPURLResponse.localizedString(forStatusCode: response.statusCode)) (\(response.statusCode))",
                NSURLErrorFailingURLErrorKey: url,
                responseErrorKey: response
            ]

            userInfo[responseDataErrorKey] = data

            let statusCodeError = NSError(domain: errorDomain, code: NSURLErrorBadServerResponse, userInfo: userInfo)
            validationError = error(statusCodeError, withUnderlyingError: validationError)

            isValid = false
        }

        return (isValid, isValid ? nil : validationError)
    }

    private static func error(_ error: NSError, withUnderlyingError underlyingError: NSError?) -> NSError {
        guard let underlyingError, error.userInfo[NSUnderlyingErrorKey] == nil else { return error }

        var userInfo = error.userInfo
        userInfo[NSUnderlyingErrorKey] = underlyingError

        return NSError(domain: error.domain, code: error.code, userInfo: userInfo)
    }

    private static func hasCode(_ code: Int, inDomain domain: String, error: NSError) -> Bool {
        if error.domain == domain, error.code == code {
            return true
        }

        if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return hasCode(code, inDomain: domain, error: underlyingError)
        }

        return false
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
