// MIT License
//
// Copyright (c) 2021 Daniel Gauthier
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//
// From https://github.com/danielmgauthier/ViewControllerTransitionExample
// SPDX-License-Identifier: MIT

import UIKit

enum OneWayPanGestureDirection {
    case up
    case down
}

class OneWayPanGestureRecognizer: UIPanGestureRecognizer {
    var drag: Bool = false
    var moveX: Int = 0
    var moveY: Int = 0
    var direction: OneWayPanGestureDirection = .down

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)

        if state == .failed {
            return
        }

        let touch: UITouch = touches.first! as UITouch
        let nowPoint: CGPoint = touch.location(in: view)
        let prevPoint: CGPoint = touch.previousLocation(in: view)
        moveX += Int(prevPoint.x - nowPoint.x)
        moveY += Int(prevPoint.y - nowPoint.y)

        if !drag {
            if moveY == 0 {
                drag = false
            } else if (direction == .down && moveY > 0) || (direction == .up && moveY < 0) {
                state = .failed
            } else {
                drag = true
            }
        }
    }

    override func reset() {
        super.reset()
        drag = false
        moveX = 0
        moveY = 0
    }
}
