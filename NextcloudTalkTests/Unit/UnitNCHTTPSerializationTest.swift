//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitNCHTTPSerializationTest: XCTestCase {

    // Expected values are what AFNetworking 3.2 produced

    func testQueryString() {
        let queryString = NCHTTPSerialization.queryString(from:)
        let noValue: String? = nil
        let someValue: String? = "v"

        XCTAssertEqual(queryString(["b": "2", "a": "1"]), "a=1&b=2")
        XCTAssertEqual(queryString(["silent": true, "x": false, "n": 5, "d": 0.5]), "d=0.5&n=5&silent=1&x=0")
        XCTAssertEqual(queryString(["options": ["A", "B & C"]]), "options%5B%5D=A&options%5B%5D=B%20%26%20C")
        XCTAssertEqual(queryString(["a": ["y": "2", "x": "1"]]), "a%5Bx%5D=1&a%5By%5D=2")
        XCTAssertEqual(queryString(["tags": [["id": 1, "name": "x"]]]), "tags%5B%5D%5Bid%5D=1&tags%5B%5D%5Bname%5D=x")
        XCTAssertEqual(queryString(["a": noValue as Any, "b": someValue as Any]), "a&b=v")
        XCTAssertEqual(queryString(["a": NSNull()]), "a")
        XCTAssertEqual(queryString(["s": Set(["b", "a"])]), "s=a&s=b")
        XCTAssertEqual(queryString(["m": ":#[]@!$&'()*+,;=?/ é😀"]), "m=%3A%23%5B%5D%40%21%24%26%27%28%29%2A%2B%2C%3B%3D?/%20%C3%A9%F0%9F%98%80")
        XCTAssertEqual(queryString([String: Any]()), "")
    }

    func testRequest() throws {
        func request(_ method: String, _ urlString: String, _ parameters: Any?) throws -> URLRequest {
            return try XCTUnwrap(NCHTTPSerialization.request(withMethod: method, urlString: urlString, parameters: parameters, headers: ["Accept": "application/json"], timeoutInterval: nil))
        }

        XCTAssertEqual(try request("GET", "https://x.test/a", ["k": "v"]).url?.absoluteString, "https://x.test/a?k=v")
        XCTAssertEqual(try request("GET", "https://x.test/a?f=1", ["k": "v"]).url?.absoluteString, "https://x.test/a?f=1&k=v")
        XCTAssertEqual(try request("DELETE", "https://x.test/a", ["k": "v"]).url?.absoluteString, "https://x.test/a?k=v")
        XCTAssertNil(try request("GET", "https://x.test/a", ["k": "v"]).httpBody)

        let post = try request("POST", "https://x.test/a", ["k": "v w"])
        XCTAssertEqual(post.httpBody, Data("k=v%20w".utf8))
        XCTAssertEqual(post.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertEqual(post.value(forHTTPHeaderField: "Accept"), "application/json")

        XCTAssertEqual(try request("PUT", "https://x.test/a", nil).httpBody, Data())
    }

    func testResponse() throws {
        func response(_ statusCode: Int, _ mimeType: String?) -> HTTPURLResponse {
            let headers = mimeType.map { ["Content-Type": $0] }
            return HTTPURLResponse(url: URL(string: "https://x.test")!, statusCode: statusCode, httpVersion: nil, headerFields: headers)!
        }

        let json = Data(#"{"ocs":{"data":{"a":1}}}"#.utf8)

        var result = NCHTTPSerialization.responseObject(for: response(200, "application/json; charset=utf-8"), data: json, type: .json)
        XCTAssertNil(result.error)
        XCTAssertNotNil(result.responseObject as? [String: Any])

        // Error responses fail, but keep the body for OcsError
        result = NCHTTPSerialization.responseObject(for: response(404, "application/json"), data: json, type: .json)
        let notFoundError = try XCTUnwrap(result.error as? NCHTTPResponseError)
        XCTAssertEqual(notFoundError.reason, .unacceptableStatusCode)
        XCTAssertEqual(notFoundError.data, json)
        XCTAssertEqual(notFoundError.response.statusCode, 404)
        XCTAssertEqual((notFoundError as NSError).code, NSURLErrorBadServerResponse)

        // Long polling relies on 304 failing
        result = NCHTTPSerialization.responseObject(for: response(304, nil), data: Data(), type: .json)
        XCTAssertEqual((result.error as? NCHTTPResponseError)?.reason, .unacceptableStatusCode)

        result = NCHTTPSerialization.responseObject(for: response(200, "text/html"), data: Data("<html>".utf8), type: .json)
        XCTAssertEqual((result.error as? NCHTTPResponseError)?.reason, .unacceptableContentType)
        XCTAssertEqual((result.error as NSError?)?.code, NSURLErrorCannotDecodeContentData)
        XCTAssertNil(result.responseObject)

        result = NCHTTPSerialization.responseObject(for: response(500, "text/html"), data: Data("<html>".utf8), type: .json)
        let htmlServerError = try XCTUnwrap(result.error as? NCHTTPResponseError)
        XCTAssertEqual(htmlServerError.reason, .unacceptableStatusCode)
        XCTAssertEqual(htmlServerError.response.mimeType, "text/html")
        XCTAssertNil(result.responseObject)

        // A broken body on an error status keeps the status error and its body on top
        result = NCHTTPSerialization.responseObject(for: response(500, "application/json"), data: Data("{bad".utf8), type: .json)
        let brokenJSONError = try XCTUnwrap(result.error as? NCHTTPResponseError)
        XCTAssertEqual(brokenJSONError.reason, .unacceptableStatusCode)
        XCTAssertEqual(brokenJSONError.data, Data("{bad".utf8))

        result = NCHTTPSerialization.responseObject(for: response(200, "application/json"), data: Data("{bad".utf8), type: .json)
        XCTAssertNotNil(result.error)

        result = NCHTTPSerialization.responseObject(for: response(204, nil), data: Data(), type: .json)
        XCTAssertNil(result.error)
        XCTAssertNil(result.responseObject)

        result = NCHTTPSerialization.responseObject(for: response(207, "application/xml"), data: Data("<x/>".utf8), type: .data)
        XCTAssertNil(result.error)
        XCTAssertEqual(result.responseObject as? Data, Data("<x/>".utf8))
    }

    func testOcsErrorReadsResponseBody() throws {
        let response = try XCTUnwrap(HTTPURLResponse(url: URL(string: "https://x.test")!, statusCode: 403, httpVersion: nil, headerFields: ["Content-Type": "application/json"]))
        let body = Data(#"{"ocs":{"meta":{"statuscode":403},"data":{"error":"permissions"}}}"#.utf8)

        let result = NCHTTPSerialization.responseObject(for: response, data: body, type: .json)
        let error = try XCTUnwrap(result.error)

        // OcsError keeps the typed error, the body must not depend on NSError bridging
        let ocsError = OcsError(withError: error, withTask: nil)
        XCTAssertEqual(ocsError.errorKey, "permissions")
        XCTAssertEqual(ocsError.underlyingError.code, NSURLErrorBadServerResponse)
    }

    func testMultipartFormData() {
        let formData = NCMultipartFormData()
        formData.appendPart(withFileData: Data("IMG".utf8), name: "files[]", fileName: "avatar.jpg", mimeType: "image/jpeg")

        let boundary = formData.boundary
        let expected = "--\(boundary)\r\nContent-Disposition: form-data; name=\"files[]\"; filename=\"avatar.jpg\"\r\nContent-Type: image/jpeg\r\n\r\nIMG\r\n--\(boundary)--\r\n"

        XCTAssertEqual(String(data: formData.body, encoding: .utf8), expected)
        XCTAssertEqual(formData.contentType, "multipart/form-data; boundary=\(boundary)")
    }
}
