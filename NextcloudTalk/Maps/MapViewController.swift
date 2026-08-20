//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import CoreLocation
import MapKit

class MapViewController: UIViewController,
                         CLLocationManagerDelegate,
                         MKMapViewDelegate {

    private static let annotationReuseIdentifier = "SharedLocationAnnotationView"

    @IBOutlet weak var mapView: MKMapView!

    private var locationManager: CLLocationManager!
    private let sharedLocationAnnotation: MKPointAnnotation

    init(geoLocationRichObject geoLocation: GeoLocationRichObject) {
        self.sharedLocationAnnotation = MKPointAnnotation()
        self.sharedLocationAnnotation.coordinate = CLLocationCoordinate2D(latitude: Double(geoLocation.latitude) ?? 0,
                                                                         longitude: Double(geoLocation.longitude) ?? 0)
        self.sharedLocationAnnotation.title = geoLocation.name

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        NCAppBranding.styleViewController(self)

        self.navigationItem.title = NSLocalizedString("Shared location", comment: "")

        locationManager = CLLocationManager()
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()

        self.mapView.delegate = self
        self.centerMapViewInSharedLocation()
        self.mapView.addAnnotation(self.sharedLocationAnnotation)

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel,
                                                                target: self,
                                                                action: #selector(cancelButtonPressed))

        let shareButton = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain, target: nil, action: nil)
        shareButton.menu = self.shareOptionsMenu()
        self.navigationItem.rightBarButtonItem = shareButton
    }

    // MARK: - Actions

    @objc func cancelButtonPressed() {
        self.dismiss(animated: true)
    }

    private func shareOptionsMenu() -> UIMenu {
        var actions: [UIAction] = []

        actions.append(UIAction(title: NSLocalizedString("Open in Maps", comment: ""), image: nil, identifier: nil) { [weak self] _ in
            guard let self else { return }

            self.openInMaps(self.sharedLocationAnnotation.coordinate)
        })

        if let googleMapsUrl = URL(string: "comgooglemaps://"), UIApplication.shared.canOpenURL(googleMapsUrl) {
            actions.append(UIAction(title: NSLocalizedString("Open in Google Maps", comment: ""), image: nil, identifier: nil) { [weak self] _ in
                guard let self else { return }

                self.openInGoogleMaps(self.sharedLocationAnnotation.coordinate)
            })
        }

        return UIMenu(title: "", children: actions)
    }

    // MARK: - Map view

    private func centerMapViewInSharedLocation() {
        let mapRegion = MKCoordinateRegion(center: self.sharedLocationAnnotation.coordinate,
                                           span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005))

        self.mapView.setRegion(mapRegion, animated: true)
    }

    // MARK: - Utils

    private func openInMaps(_ coordinate: CLLocationCoordinate2D) {
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        mapItem.name = NSLocalizedString("Shared location", comment: "")

        mapItem.openInMaps(launchOptions: [MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: coordinate)])
    }

    private func openInGoogleMaps(_ coordinate: CLLocationCoordinate2D) {
        let urlString = String(format: "comgooglemaps://?q=%f,%f&center=%f,%f&zoom=14",
                               coordinate.latitude, coordinate.longitude,
                               coordinate.latitude, coordinate.longitude)

        guard let url = URL(string: urlString), UIApplication.shared.canOpenURL(url) else { return }

        UIApplication.shared.open(url)
    }

    // MARK: - MKMapViewDelegate

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        // If the annotation is the user location, just return nil.
        if annotation is MKUserLocation {
            return nil
        }

        guard annotation === self.sharedLocationAnnotation else { return nil }

        if let pinView = mapView.dequeueReusableAnnotationView(withIdentifier: Self.annotationReuseIdentifier) as? MKPinAnnotationView {
            pinView.annotation = annotation

            return pinView
        }

        let pinView = MKPinAnnotationView(annotation: annotation, reuseIdentifier: Self.annotationReuseIdentifier)
        pinView.pinTintColor = NCAppBranding.elementColor()
        pinView.animatesDrop = true
        pinView.canShowCallout = true

        return pinView
    }
}
