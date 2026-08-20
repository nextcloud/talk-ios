//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

let geoLocationRichObjectType = "geo-location"

@objcMembers public class GeoLocationRichObject: NSObject {

    public var objectType: String
    public var objectId: String
    public var latitude: String
    public var longitude: String
    public var name: String

    public init(latitude: Double, longitude: Double, name: String) {
        // NSNumber.stringValue renders a whole number as "48", String(Double) would render "48.0" into the objectId
        let latitudeString = NSNumber(value: latitude).stringValue
        let longitudeString = NSNumber(value: longitude).stringValue

        self.objectType = geoLocationRichObjectType
        self.objectId = "geo:\(latitudeString),\(longitudeString)"
        self.latitude = latitudeString
        self.longitude = longitudeString
        self.name = name

        super.init()
    }

    public init(from parameter: NCMessageLocationParameter) {
        self.objectType = parameter.type
        self.objectId = parameter.parameterId
        self.latitude = parameter.latitude ?? ""
        self.longitude = parameter.longitude ?? ""
        self.name = parameter.name

        super.init()
    }

    private var metaData: [String: String] {
        return ["latitude": self.latitude,
                "longitude": self.longitude,
                "name": self.name]
    }

    public func richObjectDictionary() -> [AnyHashable: Any] {
        var jsonString = ""

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: self.metaData)
            jsonString = String(data: jsonData, encoding: .utf8) ?? ""
        } catch {
            NSLog("Got an error: %@", error.localizedDescription)
        }

        return ["objectType": self.objectType,
                "objectId": self.objectId,
                "metaData": jsonString]
    }
}
