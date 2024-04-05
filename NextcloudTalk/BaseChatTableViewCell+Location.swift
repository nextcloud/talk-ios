//
// Copyright (c) 2024 Marcel Müller <marcel-mueller@gmx.de>
//
// Author Ivan Sein <ivan@nextcloud.com>
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

import MapKit

extension BaseChatTableViewCell {

    func setupForLocationCell(with message: NCChatMessage) {
        if self.locationPreviewImageView == nil {
            // Location preview image view
            let locationPreviewImageView = UIImageView(frame: .init(x: 0, y: 0, width: locationMessageCellPreviewWidth, height: locationMessageCellPreviewHeight))
            self.locationPreviewImageView = locationPreviewImageView

            locationPreviewImageView.translatesAutoresizingMaskIntoConstraints = false
            locationPreviewImageView.layer.cornerRadius = fileMessageCellFilePreviewCornerRadius
            locationPreviewImageView.layer.masksToBounds = true
            locationPreviewImageView.contentMode = .scaleAspectFit

            self.messageBodyView.addSubview(locationPreviewImageView)

            let previewTap = UITapGestureRecognizer(target: self, action: #selector(locationPreviewTapped))
            locationPreviewImageView.addGestureRecognizer(previewTap)
            locationPreviewImageView.isUserInteractionEnabled = true

            guard let geoLocationRichObject = message.geoLocation()
            else { return }

            let geoLocation = GeoLocationRichObject(from: geoLocationRichObject)

            guard let latitude = Double(geoLocation.latitude),
                  let longitude = Double(geoLocation.longitude)
            else { return }

            let mapView = MKMapView(frame: .init(x: 0, y: 0, width: locationMessageCellPreviewWidth, height: locationMessageCellPreviewHeight))

            let mapRegion = MKCoordinateRegion(center: .init(latitude: latitude, longitude: longitude),
                                               span: .init(latitudeDelta: 0.005, longitudeDelta: 0.005))

            let options: MKMapSnapshotter.Options = .init()
            options.region = mapRegion
            options.size = mapView.frame.size
            options.scale = UIScreen.main.scale

            let mapSnapshooter = MKMapSnapshotter(options: options)
            mapSnapshooter.start { snapshot, _ in
                guard let snapshot = snapshot
                else { return }

                let pin = MKPinAnnotationView(annotation: nil, reuseIdentifier: nil)
                let image = snapshot.image

                UIGraphicsBeginImageContextWithOptions(image.size, true, image.scale)
                image.draw(at: CGPoint.zero)

                let rect = CGRect(origin: CGPoint.zero, size: image.size)
                let annotation = MKPointAnnotation()
                annotation.coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                var point = snapshot.point(for: annotation.coordinate)
                if rect.contains(point) {
                    point.x += pin.centerOffset.x - (pin.bounds.size.width / 2)
                    point.y += pin.centerOffset.y - (pin.bounds.size.height / 2)
                    pin.pinTintColor = NCAppBranding.elementColor()
                    pin.image?.draw(at: point)
                }

                let compositeImage = UIGraphicsGetImageFromCurrentImageContext()
                self.locationPreviewImageView?.image = compositeImage
                UIGraphicsEndImageContext()
            }

            // Add everything to messageBodyView
            let heightConstraint = locationPreviewImageView.heightAnchor.constraint(equalToConstant: locationMessageCellPreviewHeight)
            let widthConstraint = locationPreviewImageView.widthAnchor.constraint(equalToConstant: locationMessageCellPreviewWidth)

            self.locationPreviewImageViewHeightConstraint = heightConstraint
            self.locationPreviewImageViewWidthConstraint = widthConstraint

            let messageTextView = MessageBodyTextView()
            self.messageTextView = messageTextView

            messageTextView.translatesAutoresizingMaskIntoConstraints = false

            self.messageBodyView.addSubview(messageTextView)

            NSLayoutConstraint.activate([
                locationPreviewImageView.leftAnchor.constraint(equalTo: self.messageBodyView.leftAnchor),
                locationPreviewImageView.topAnchor.constraint(equalTo: self.messageBodyView.topAnchor),
                heightConstraint,
                widthConstraint,
                messageTextView.leftAnchor.constraint(equalTo: self.messageBodyView.leftAnchor),
                messageTextView.rightAnchor.constraint(equalTo: self.messageBodyView.rightAnchor),
                messageTextView.topAnchor.constraint(equalTo: locationPreviewImageView.bottomAnchor, constant: 10),
                messageTextView.bottomAnchor.constraint(equalTo: self.messageBodyView.bottomAnchor)
            ])
        }

        guard let messageTextView = self.messageTextView
        else { return }

        messageTextView.attributedText = message.parsedMarkdownForChat()
    }

    func prepareForReuseLocationCell() {
        self.locationPreviewImageView = nil
    }

    @objc func locationPreviewTapped() {
        guard let geoLocationRichObject = self.message?.geoLocation()
        else { return }

        let geoLocation = GeoLocationRichObject(from: geoLocationRichObject)

        self.delegate?.cellWants(toOpenLocation: geoLocation)
    }
}
