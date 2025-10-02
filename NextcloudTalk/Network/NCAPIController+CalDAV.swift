//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import SwiftyXMLParser

struct NCCalendar {
    let calendarUri: String
    let displayName: String
}

extension NCAPIController {

    func getCalendars(forAccount account: TalkAccount, completionBlock: @escaping (_ calendars: [NCCalendar]) -> Void) {
        guard let calDAVSessionManager = self.calDAVSessionManagers.object(forKey: account.accountId) as? NCCalDAVSessionManager
        else {
            completionBlock([])
            return
        }

        let xmlBody = """
                <?xml version="1.0" encoding="UTF-8"?>
                <d:propfind xmlns:d="DAV:">
                    <d:prop>
                        <d:displayname/>
                        <d:resourcetype/>
                        <d:current-user-privilege-set/>
                    </d:prop>
                </d:propfind>
                """

        let urlString = "\(account.server)/remote.php/dav/calendars/\(account.userId)/"
        let request = calDAVSessionManager.requestSerializer.request(withMethod: "PROPFIND", urlString: urlString, parameters: nil, error: nil)
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.httpBody = xmlBody.data(using: .utf8)

        let task = calDAVSessionManager.dataTask(with: request as URLRequest) { _, responseObject, error in
            guard error == nil, let responseData = responseObject as? Data else {
                completionBlock([])
                return
            }

            let calendars = self.getWritableCalendars(xmlData: responseData)
            completionBlock(calendars)
        }

        task.resume()
    }

    private func getWritableCalendars(xmlData: Data) -> [NCCalendar] {
        let xml = XML.parse(xmlData)
        var writableCalendars: [NCCalendar] = []

        for element in xml["d:multistatus", "d:response"] {
            let href = element["d:href"].text?.split(separator: "/").last
            let displayName = element["d:propstat", "d:prop", "d:displayname"].text
            let isCalendar = element["d:propstat", "d:prop", "d:resourcetype", "cal:calendar"].element != nil

            var canCreateEvent = false
            for privilege in element["d:propstat", "d:prop", "d:current-user-privilege-set", "d:privilege"] {
                if privilege["d:bind"].element != nil || privilege["d:write"].element != nil || privilege["d:write-content"].element != nil {
                    canCreateEvent = true
                    break
                }
            }

            if let calendarUri = href, let calendarName = displayName, isCalendar, canCreateEvent {
                let calendar = NCCalendar(calendarUri: String(calendarUri), displayName: calendarName)
                writableCalendars.append(calendar)
            }
        }

        return writableCalendars
    }

    public enum CreateMeetingResponse: Int {
        case unknownError = 0
        case success = 1
        case calendarError = 2
        case emailError = 3
        case startError = 4
        case endError = 5

        init(errorKey: String?) {
            switch errorKey {
            case nil: self = .success
            case "calendar": self = .calendarError
            case "email": self = .emailError
            case "start": self = .startError
            case "end": self = .endError
            default: self = .unknownError
            }
        }
    }

    // swiftlint:disable function_parameter_count
    public func createMeeting(account: TalkAccount, token: String, title: String?, description: String?, start: Int, end: Int, calendarUri: String, attendeeIds: [Int]?, completionBlock: @escaping (_ error: CreateMeetingResponse) -> Void) {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else {
            completionBlock(.unknownError)
            return
        }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/meeting", for: account)
        var parameters: [String: Any] = ["calendarUri": calendarUri]
        parameters["start"] = start
        parameters["end"] = end

        if let title, !title.isEmpty {
            parameters["title"] = title
        }

        if let description, !description.isEmpty {
            parameters["description"] = description
        }

        if let attendeeIds, !attendeeIds.isEmpty {
            parameters["attendeeIds"] = attendeeIds
        }

        apiSessionManager.postOcs(urlString, account: account, parameters: parameters) { _, ocsError in
            completionBlock(CreateMeetingResponse(errorKey: ocsError?.errorKey))
        }
    }
}
