//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import CoreLocation
import MapKit

protocol ShareLocationViewControllerDelegate: AnyObject {
    func shareLocationViewController(_ viewController: ShareLocationViewController, didSelectLocationWithLatitude latitude: Double, longitude: Double, andName name: String)
}

class ShareLocationViewController: UIViewController,
                                   CLLocationManagerDelegate,
                                   MKMapViewDelegate,
                                   UITableViewDelegate,
                                   UITableViewDataSource,
                                   UISearchControllerDelegate,
                                   UISearchResultsUpdating {

    private enum ShareLocationSection: Int, CaseIterable {
        case current = 0
        case dropPin
        case nearby
    }

    weak var delegate: ShareLocationViewControllerDelegate?

    @IBOutlet weak var mapView: MKMapView!
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var myLocationButton: UIButton!

    private var searchController: UISearchController!
    private var resultTableViewController: UITableViewController!
    private var locationManager: CLLocationManager!
    private var currentLocation: CLLocation?
    private var nearbyPlaces: [MKMapItem] = []
    private var searchedPlaces: [MKMapItem] = []
    private var hasBeenCentered = false
    private var dropPinAnnotation: MKPointAnnotation?
    private var dropPinPlacemark: CLPlacemark?
    private var dropPinGuideView: UIView?
    private let iconsConfiguration = UIImage.SymbolConfiguration(pointSize: 20)

    override func viewDidLoad() {
        super.viewDidLoad()

        resultTableViewController = UITableViewController()
        resultTableViewController.tableView.delegate = self
        resultTableViewController.tableView.dataSource = self
        resultTableViewController.tableView.tableFooterView = UIView(frame: .zero)

        searchController = UISearchController(searchResultsController: resultTableViewController)
        searchController.delegate = self
        searchController.searchResultsUpdater = self
        searchController.hidesNavigationBarDuringPresentation = false
        searchController.searchBar.sizeToFit()

        self.navigationItem.searchController = searchController

        NCAppBranding.styleViewController(self)

        searchController.searchBar.searchTextField.attributedPlaceholder = NSAttributedString(string: NSLocalizedString("Search for places", comment: ""))

        self.navigationItem.title = NSLocalizedString("Share location", comment: "")

        locationManager = CLLocationManager()
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()

        self.mapView.delegate = self
        self.mapView.showsUserLocation = true

        self.myLocationButton.layer.cornerRadius = 22
        self.myLocationButton.clipsToBounds = true

        self.tableView.delegate = self
        self.tableView.dataSource = self
        self.tableView.tableFooterView = UIView(frame: .zero)

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelButtonPressed))

        // Place resultTableViewController correctly
        self.definesPresentationContext = true
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        self.myLocationButton.isHidden = true

        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            self.myLocationButton.isHidden = false
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied:
            self.showAuthorizationStatusDeniedAlert()
        default:
            break
        }
    }

    private func showAuthorizationStatusDeniedAlert() {
        let alert = UIAlertController(title: NSLocalizedString("Could not access your location", comment: ""),
                                      message: NSLocalizedString("Location service has been denied. Check your settings.", comment: ""),
                                      preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: ""), style: .default) { _ in
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsURL)
            }
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel))

        self.present(alert, animated: true)
    }

    // MARK: - MKMapViewDelegate

    func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
        // Center the map view the first time the user location is updated
        if !hasBeenCentered {
            hasBeenCentered = true
            self.centerMapViewToUserLocation()
        }

        DispatchQueue.main.async {
            self.currentLocation = mapView.userLocation.location
            self.tableView.reloadSections(IndexSet(integer: ShareLocationSection.current.rawValue), with: .none)
        }
    }

    func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
        if let dropPinAnnotation {
            self.mapView.removeAnnotation(dropPinAnnotation)
        }

        self.showDropPinGuideView()
    }

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        self.hideDropPinGuideView()

        let annotation = MKPointAnnotation()
        annotation.coordinate = CLLocationCoordinate2D(latitude: self.mapView.centerCoordinate.latitude, longitude: self.mapView.centerCoordinate.longitude)
        self.mapView.addAnnotation(annotation)
        dropPinAnnotation = annotation

        let location = CLLocation(latitude: annotation.coordinate.latitude, longitude: annotation.coordinate.longitude)
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, error in
            if error == nil, let placemark = placemarks?.first {
                DispatchQueue.main.async {
                    self.dropPinPlacemark = placemark
                    self.tableView.reloadSections(IndexSet(integer: ShareLocationSection.dropPin.rawValue), with: .none)
                }
            }
        }
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        // If the annotation is the user location, just return nil.
        if annotation is MKUserLocation {
            return nil
        }

        if let dropPinAnnotation, annotation === dropPinAnnotation {
            let identifier = "SelectedLocationAnnotationView"

            if let pinView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKPinAnnotationView {
                pinView.annotation = annotation
                return pinView
            }

            let pinView = MKPinAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            pinView.pinTintColor = NCAppBranding.elementColor()
            pinView.animatesDrop = true
            pinView.canShowCallout = true
            return pinView
        }

        return nil
    }

    // MARK: - Actions

    @objc private func cancelButtonPressed() {
        self.dismiss(animated: true)
    }

    @IBAction func myLocationButtonPressed(_ sender: Any) {
        self.centerMapViewToUserLocation()
    }

    // MARK: - Map View

    private func centerMapViewToUserLocation() {
        let mapRegion = MKCoordinateRegion(center: self.mapView.userLocation.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
        self.mapView.setRegion(mapRegion, animated: true)
    }

    private func showDropPinGuideView() {
        let guideView = UIView(frame: CGRect(x: 0, y: 0, width: 8, height: 8))
        guideView.backgroundColor = NCAppBranding.placeholderColor()
        guideView.layer.cornerRadius = 4
        guideView.clipsToBounds = true

        guideView.center = self.mapView.center

        self.mapView.addSubview(guideView)
        self.mapView.bringSubviewToFront(guideView)
        dropPinGuideView = guideView
    }

    private func hideDropPinGuideView() {
        dropPinGuideView?.removeFromSuperview()
        dropPinAnnotation = nil
    }

    // MARK: - Search places

    private func searchForNearbyPlaces() {
        let request = MKLocalPointsOfInterestRequest(coordinateRegion: self.mapView.region)
        let search = MKLocalSearch(request: request)
        search.start { response, _ in
            if let response {
                DispatchQueue.main.async {
                    self.nearbyPlaces = response.mapItems
                    self.tableView.reloadSections(IndexSet(integer: ShareLocationSection.nearby.rawValue), with: .none)
                }
            }
        }
    }

    private func searchForPlaces(with searchString: String) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchString

        let search = MKLocalSearch(request: request)
        search.start { response, _ in
            if let response {
                DispatchQueue.main.async {
                    self.searchedPlaces = response.mapItems
                    self.resultTableViewController.tableView.reloadData()
                }
            }
        }
    }

    // MARK: - Search controller

    func updateSearchResults(for searchController: UISearchController) {
        self.searchForPlaces(with: self.searchController.searchBar.text ?? "")
    }

    // MARK: - UITableView delegate and data source

    func numberOfSections(in tableView: UITableView) -> Int {
        if tableView == resultTableViewController.tableView {
            return 1
        }

        return ShareLocationSection.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if tableView == resultTableViewController.tableView {
            return searchedPlaces.count
        }

        switch ShareLocationSection(rawValue: section) {
        case .current:
            return currentLocation != nil ? 1 : 0
        case .dropPin:
            return 1
        case .nearby:
            return nearbyPlaces.count
        default:
            return 0
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == ShareLocationSection.nearby.rawValue, !nearbyPlaces.isEmpty {
            return NSLocalizedString("Nearby places", comment: "")
        }

        return nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // Search result table view
        if tableView == resultTableViewController.tableView {
            let searchedPlace = searchedPlaces[indexPath.row]
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "SearchedLocationCellIdentifier")
            cell.imageView?.image = UIImage(systemName: "mappin", withConfiguration: iconsConfiguration)
            cell.imageView?.tintColor = .secondaryLabel
            cell.textLabel?.text = searchedPlace.name

            var subtitle: String?
            if let thoroughfare = searchedPlace.placemark.thoroughfare, let subThoroughfare = searchedPlace.placemark.subThoroughfare {
                subtitle = "\(thoroughfare) \(subThoroughfare), "
            }
            if let locality = searchedPlace.placemark.locality {
                subtitle = subtitle?.appending("\(locality), ")
            }
            if let country = searchedPlace.placemark.country {
                subtitle = subtitle?.appending(country)
            }
            cell.detailTextLabel?.text = subtitle

            return cell
        }

        // Main view table view
        switch ShareLocationSection(rawValue: indexPath.section) {
        case .current:
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "UserLocationCellIdentifier")
            cell.imageView?.image = UIImage(systemName: "location.fill", withConfiguration: iconsConfiguration)
            cell.textLabel?.text = NSLocalizedString("Share current location", comment: "")
            cell.detailTextLabel?.text = String(format: "%@: %.0fm", NSLocalizedString("Accuracy", comment: ""), currentLocation?.horizontalAccuracy ?? 0)
            return cell
        case .dropPin:
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "DropPinCellIdentifier")
            cell.imageView?.image = UIImage(systemName: "mappin", withConfiguration: iconsConfiguration)
            cell.textLabel?.text = NSLocalizedString("Share pin location", comment: "Share the location of a pin that has been dropped in a map view")
            if let thoroughfare = dropPinPlacemark?.thoroughfare, let subThoroughfare = dropPinPlacemark?.subThoroughfare {
                cell.detailTextLabel?.text = "\(thoroughfare) \(subThoroughfare)"
            }
            return cell
        case .nearby:
            let nearbyPlace = nearbyPlaces[indexPath.row]
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "NearbyLocationCellIdentifier")
            cell.imageView?.image = UIImage(systemName: "mappin", withConfiguration: iconsConfiguration)
            cell.imageView?.tintColor = .secondaryLabel
            cell.textLabel?.text = nearbyPlace.name
            cell.detailTextLabel?.text = nil
            if let thoroughfare = nearbyPlace.placemark.thoroughfare, let subThoroughfare = nearbyPlace.placemark.subThoroughfare {
                cell.detailTextLabel?.text = "\(thoroughfare) \(subThoroughfare)"
            }
            return cell
        default:
            return UITableViewCell()
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        // Search result table view
        if tableView == resultTableViewController.tableView {
            let searchedPlace = searchedPlaces[indexPath.row]
            if let location = searchedPlace.placemark.location {
                self.delegate?.shareLocationViewController(self, didSelectLocationWithLatitude: location.coordinate.latitude, longitude: location.coordinate.longitude, andName: searchedPlace.name ?? "")
            }
            self.dismiss(animated: true)
            return
        }

        // Main view table view
        switch ShareLocationSection(rawValue: indexPath.section) {
        case .current:
            if let currentLocation {
                self.delegate?.shareLocationViewController(self, didSelectLocationWithLatitude: currentLocation.coordinate.latitude, longitude: currentLocation.coordinate.longitude, andName: NSLocalizedString("My location", comment: ""))
            }
        case .dropPin:
            var locationName = NSLocalizedString("Shared location", comment: "")
            if let thoroughfare = dropPinPlacemark?.thoroughfare, let subThoroughfare = dropPinPlacemark?.subThoroughfare {
                locationName = "\(thoroughfare) \(subThoroughfare)"
            }
            if let dropPinAnnotation {
                self.delegate?.shareLocationViewController(self, didSelectLocationWithLatitude: dropPinAnnotation.coordinate.latitude, longitude: dropPinAnnotation.coordinate.longitude, andName: locationName)
            }
        case .nearby:
            let nearbyPlace = nearbyPlaces[indexPath.row]
            if let location = nearbyPlace.placemark.location {
                self.delegate?.shareLocationViewController(self, didSelectLocationWithLatitude: location.coordinate.latitude, longitude: location.coordinate.longitude, andName: nearbyPlace.name ?? "")
            }
        default:
            break
        }
    }
}
