//
//  Atomic.swift
//  Broadcast Extension
//
//  Created by Maksym Shcheglov.
//  https://www.onswiftwings.com/posts/atomic-property-wrapper/
//
// From https://github.com/jitsi/jitsi-meet-sdk-samples (Apache 2.0 license)
//
// SPDX-FileCopyrightText: Maksym Shcheglov
// SPDX-License-Identifier: Apache-2.0
//

import Foundation

@propertyWrapper
struct Atomic<Value> {

    private var value: Value
    private let lock = NSLock()

    init(wrappedValue value: Value) {
        self.value = value
    }

    var wrappedValue: Value {
        get { load() }
        set { store(newValue: newValue) }
    }

    func load() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    mutating func store(newValue: Value) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }
}
