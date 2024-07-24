//
// SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

// See https://github.com/nextcloud/nextcloud-vue/blob/56b79afae93f4701a0cb933bfeb7b4a2fbd590fb/src/functions/usernameToColor/usernameToColor.js
// and https://github.com/nextcloud/nextcloud-vue/blob/56b79afae93f4701a0cb933bfeb7b4a2fbd590fb/src/utils/GenColors.js

import Foundation
import CryptoKit

@objcMembers class ColorGenerator: NSObject {

    public static let shared = ColorGenerator()

    private let steps = 6
    private let finalPalette: [UIColor]

    // See: https://stackoverflow.com/a/22334560
    private static let multiplier = CGFloat(255.999999)

    private override init() {
        finalPalette = ColorGenerator.genColors(steps)

        super.init()
    }

    private static func stepCalc(_ steps: Int, _ ends: [UIColor]) -> [CGFloat] {
        var step: [CGFloat] = [0, 0, 0]

        var red0: CGFloat = 0
        var green0: CGFloat = 0
        var blue0: CGFloat = 0

        var red1: CGFloat = 0
        var green1: CGFloat = 0
        var blue1: CGFloat = 0

        ends[0].getRed(&red0, green: &green0, blue: &blue0, alpha: nil)
        ends[1].getRed(&red1, green: &green1, blue: &blue1, alpha: nil)

        step[0] = (red1 - red0) / CGFloat(steps)
        step[1] = (green1 - green0) / CGFloat(steps)
        step[2] = (blue1 - blue0) / CGFloat(steps)

        return step
    }

    private static func mixPalette(_ steps: Int, _ color1: UIColor, _ color2: UIColor) -> [UIColor] {
        var palette: [UIColor] = [color1]

        let step = stepCalc(steps, [color1, color2])

        for i in 1...steps - 1 {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0

            color1.getRed(&red, green: &green, blue: &blue, alpha: nil)
            let r = abs(red + step[0] * CGFloat(i))
            let g = abs(green + step[1] * CGFloat(i))
            let b = abs(blue + step[2] * CGFloat(i))

            palette.append(UIColor(red: r, green: g, blue: b, alpha: 1))
        }

        return palette
    }

    public static func genColors(_ steps: Int) -> [UIColor] {
        let red = UIColor(red: 182 / multiplier, green: 70 / multiplier, blue: 157 / multiplier, alpha: 1)
        let yellow = UIColor(red: 221 / multiplier, green: 203 / multiplier, blue: 85 / multiplier, alpha: 1)
        let blue = UIColor(red: 0, green: 130 / multiplier, blue: 201 / multiplier, alpha: 1)

        var palette1 = mixPalette(steps, red, yellow)
        let palette2 = mixPalette(steps, yellow, blue)
        let palette3 = mixPalette(steps, blue, red)

        palette1.append(contentsOf: palette2)
        palette1.append(contentsOf: palette3)

        return palette1
    }

    public func usernameToColor(_ username: String) -> UIColor {
        let hash = username.lowercased()
        var hashInt = 0

        if let usernameData = hash.data(using: .utf8) {
            let md5Hash = Insecure.MD5.hash(data: usernameData)
            let t = md5Hash.map { String(format: "%02hhx", $0) }.joined()
            hashInt = t.map { Int(String($0), radix: 16)! % 16}.reduce(0, +)
        }

        let maximum = steps * 3
        hashInt = hashInt % maximum

        return finalPalette[hashInt]
    }
}
