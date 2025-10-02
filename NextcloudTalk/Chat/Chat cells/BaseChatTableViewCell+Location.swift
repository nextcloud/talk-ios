//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

extension BaseChatTableViewCell {

    func setupForLocationCell(with message: NCChatMessage) {
        if self.locationPreviewImageView == nil {
            // Location preview image view
            let locationPreviewImageView = UIImageView(frame: .init(x: 0, y: 0, width: locationMessageCellPreviewWidth, height: locationMessageCellPreviewHeight))
            self.locationPreviewImageView = locationPreviewImageView

            locationPreviewImageView.translatesAutoresizingMaskIntoConstraints = false
            locationPreviewImageView.layer.cornerRadius = chatMessageCellPreviewCornerRadius
            locationPreviewImageView.layer.masksToBounds = true
            locationPreviewImageView.contentMode = .scaleAspectFit

            self.messageBodyView.addSubview(locationPreviewImageView)

            let previewTap = UITapGestureRecognizer(target: self, action: #selector(locationPreviewTapped))
            locationPreviewImageView.addGestureRecognizer(previewTap)
            locationPreviewImageView.isUserInteractionEnabled = true

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
                locationPreviewImageView.rightAnchor.constraint(lessThanOrEqualTo: self.messageBodyView.rightAnchor),
                heightConstraint,
                widthConstraint,
                messageTextView.leftAnchor.constraint(equalTo: self.messageBodyView.leftAnchor),
                messageTextView.rightAnchor.constraint(equalTo: self.messageBodyView.rightAnchor),
                messageTextView.topAnchor.constraint(equalTo: locationPreviewImageView.bottomAnchor, constant: 10),
                messageTextView.bottomAnchor.constraint(equalTo: self.messageBodyView.bottomAnchor)
            ])
        }

        guard let locationPreviewImageView = self.locationPreviewImageView,
              let messageTextView = self.messageTextView,
              let geoLocationRichObject = message.geoLocation()
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

        let locationMapSnapshooter = MKMapSnapshotter(options: options)
        self.locationMapSnapshooter = locationMapSnapshooter

        locationMapSnapshooter.start { snapshot, _ in
            guard let snapshot else { return }

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

        messageTextView.attributedText = message.parsedMarkdownForChat()
    }

    func prepareForReuseLocationCell() {
        self.locationMapSnapshooter?.cancel()
        self.locationPreviewImageView?.image = nil
    }

    @objc func locationPreviewTapped() {
        guard let geoLocationRichObject = self.message?.geoLocation()
        else { return }

        let geoLocation = GeoLocationRichObject(from: geoLocationRichObject)

        self.delegate?.cellWants(toOpenLocation: geoLocation)
    }
}
