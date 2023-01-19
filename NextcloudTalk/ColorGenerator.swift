//
// Copyright (c) 2022 Marcel Müller <marcel-mueller@gmx.de>
//
// Author Marcel Müller <marcel-mueller@gmx.de>
//
// GNU GPL version 3 or any later version
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

// See https://github.com/nextcloud/nextcloud-vue/blob/56b79afae93f4701a0cb933bfeb7b4a2fbd590fb/src/functions/usernameToColor/usernameToColor.js
// and https://github.com/nextcloud/nextcloud-vue/blob/56b79afae93f4701a0cb933bfeb7b4a2fbd590fb/src/utils/GenColors.js

import Foundation
import CryptoKit

@objcMembers class ColorGenerator: NSObject {

    public static let shared = ColorGenerator()

    private let steps = 6
    private let finalPalette: [UIColor]

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

    private static func genColors(_ steps: Int) -> [UIColor] {
        let red = UIColor(red: 182 / 255, green: 70 / 255, blue: 157 / 255, alpha: 1)
        let yellow = UIColor(red: 221 / 255, green: 203 / 255, blue: 85 / 255, alpha: 1)
        let blue = UIColor(red: 0, green: 130 / 255, blue: 201 / 255, alpha: 1)

        var palette1 = mixPalette(steps, red, yellow)
        let palette2 = mixPalette(steps, yellow, blue)
        let palette3 = mixPalette(steps, blue, red)

        palette1.append(contentsOf: palette2)
        palette1.append(contentsOf: palette3)

        return palette1
    }

    public func usernameToColor(_ username: String) -> UIColor {
        var hash = username.lowercased()
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
