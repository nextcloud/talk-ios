//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

public struct NCPoll {

    public struct PollResultDetail {
        public let actorDisplayName: String
        public let actorId: String
        public let actorType: String
        public let optionId: Int

        init(dict: [String: Any]) {
            actorDisplayName = dict["actorDisplayName"] as? String ?? ""
            actorId = dict["actorId"] as? String ?? ""
            actorType = dict["actorType"] as? String ?? ""
            optionId = dict["optionId"] as? Int ?? 0
        }
    }

    public var pollId: Int = 0
    public var question: String = ""
    public var options: [String] = []
    public var votes: [String: Int] = [:]
    public var actorType: String = ""
    public var actorId: String = ""
    public var actorDisplayName: String = ""
    public var status: NCPollStatus = .open
    public var resultMode: NCPollResultMode = .public
    public var maxVotes: Int = 0
    public var votedSelf: [Int] = []
    public var numVoters: Int = 0
    public var details: [PollResultDetail] = []
}

extension NCPoll {
    public init?(dict: [String: Any]?) {
        guard let dict else { return nil }

        pollId = dict["id"] as? Int ?? 0
        question = dict["question"] as? String ?? ""
        options = dict["options"] as? [String] ?? []
        votes = dict["votes"] as? [String: Int] ?? [:]
        actorType = dict["actorType"] as? String ?? ""
        actorId = dict["actorId"] as? String ?? ""
        actorDisplayName = dict["actorDisplayName"] as? String ?? ""
        status = NCPollStatus(rawValue: dict["status"] as? Int ?? 0) ?? .open
        resultMode = NCPollResultMode(rawValue: dict["resultMode"] as? Int ?? 0) ?? .public
        maxVotes = dict["maxVotes"] as? Int ?? 0
        votedSelf = dict["votedSelf"] as? [Int] ?? []
        numVoters = dict["numVoters"] as? Int ?? 0
        details = (dict["details"] as? [[String: Any]] ?? []).map(PollResultDetail.init)
    }
}
