//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

public typealias RoomInternalIdString = String

public class AiSummaryTask {
    public var taskIds = [Int]()
    public var outputs = [String]()
}

public class AiSummaryController {

    public static let shared = AiSummaryController()

    public var generateSummaryTasks = [RoomInternalIdString: AiSummaryTask]()

    public func addSummaryTaskId(forRoomInternalId internalId: String, withTaskId taskId: Int) {
        let task = generateSummaryTasks[internalId, default: AiSummaryTask()]

        task.taskIds.append(taskId)
        generateSummaryTasks[internalId] = task
    }

    public func markSummaryTaskAsDone(forRoomInternalId internalId: String, withTaskId taskId: Int, withOutput output: String) {
        guard let task = generateSummaryTasks[internalId] else { return }

        task.taskIds.removeAll(where: { $0 == taskId })
        task.outputs.append(output)
    }

    @discardableResult
    public func finalizeSummaryTask(forRoomInternalId internalId: String) -> [String] {
        let result = generateSummaryTasks[internalId]?.outputs ?? []
        generateSummaryTasks.removeValue(forKey: internalId)

        return result
    }

    public func getSummaryTaskIds(forRoomInternalId internalId: String) -> [Int] {
        return generateSummaryTasks[internalId]?.taskIds ?? []
    }
}
