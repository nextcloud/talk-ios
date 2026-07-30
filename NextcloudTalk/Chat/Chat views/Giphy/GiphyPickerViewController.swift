//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import SDWebImage

protocol GiphyPickerViewControllerDelegate: AnyObject {
    func giphyPickerViewController(_ controller: GiphyPickerViewController, didSelectGifWithUrl url: String)
}

class GiphyPickerViewController: UIViewController {

    public weak var delegate: GiphyPickerViewControllerDelegate?

    private let account: TalkAccount
    private let pageLimit = 20
    private let searchDebounceInterval: TimeInterval = 0.5

    /// A GIF with the aspect ratio the masonry layout places it with. GIFs only enter this list once
    /// their thumbnail has been measured, so that a placed item never has to move again.
    private struct GridItem {
        let gif: GiphyGif
        let aspectRatio: CGFloat
    }

    /// Keeps a GIF whose thumbnail failed to load as a sensibly sized tile instead of dropping it
    private static let fallbackAspectRatio: CGFloat = 1.0

    /// Space kept free at the end of the grid for the loading indicator. Doubles as the distance from
    /// the end within which the indicator shows, i.e. once that space has been scrolled into view.
    private static let loadingMoreIndicatorHeight: CGFloat = 44.0

    /// Shared by measuring a GIF and displaying it, so that both hit the same cache entries.
    private lazy var imageContext = NCAPIController.sharedInstance().giphyImageContext(forAccount: self.account)

    private var items: [GridItem] = []
    private var cursor = 0
    private var hasMore = true
    private var isLoading = false
    private var currentTerm = ""
    // Incremented whenever the query changes, to invalidate in-flight requests.
    private var generation = 0
    private var loadTask: Task<Void, Never>?
    private var searchDebounceWorkItem: DispatchWorkItem?

    private lazy var searchController: UISearchController = {
        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.searchBar.placeholder = NSLocalizedString("Search GIFs", comment: "")
        searchController.searchBar.autocapitalizationType = .none
        searchController.searchBar.autocorrectionType = .no
        searchController.searchBar.delegate = self
        // Keep the Cancel button visible while typing …
        searchController.hidesNavigationBarDuringPresentation = false
        // … and, more importantly, no dimming view over the collection view while the search is
        // active: it swallows the first tap on a GIF, which is why selecting one needed two taps.
        searchController.obscuresBackgroundDuringPresentation = false
        return searchController
    }()

    private lazy var waterfallLayout: GiphyWaterfallLayout = {
        let layout = GiphyWaterfallLayout()
        layout.delegate = self
        return layout
    }()

    private lazy var collectionView: UICollectionView = {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: self.waterfallLayout)
        collectionView.backgroundColor = .systemBackground
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .onDrag
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(GiphyGifCell.self, forCellWithReuseIdentifier: GiphyGifCell.identifier)
        return collectionView
    }()

    private lazy var activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.hidesWhenStopped = true
        indicator.color = .secondaryLabel
        return indicator
    }()

    /// Shown while another page is loading. Pinned to the screen rather than being a footer below the
    /// last GIF: a footer lives in the content, so it moves while scrolling and as GIFs are appended.
    private lazy var loadingMoreIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.color = .secondaryLabel
        return indicator
    }()

    private lazy var emptyLabel: UILabel = {
        let label = UILabel()
        label.text = NSLocalizedString("No results", comment: "")
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.isHidden = true
        return label
    }()

    init(account: TalkAccount) {
        self.account = account
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = .systemBackground
        // Not localized: "GIF" is a file format and "Giphy" a company name
        self.navigationItem.title = "GIF (Giphy)"
        self.navigationItem.searchController = self.searchController
        // Keep the search bar reachable at all times, instead of having to scroll the grid
        // back to the top to refine the search term.
        self.navigationItem.hidesSearchBarWhenScrolling = false
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(self.cancelButtonPressed))
        // Fix uisearchcontroller animation
        self.extendedLayoutIncludesOpaqueBars = true

        self.view.addSubview(self.collectionView)
        self.view.addSubview(self.activityIndicator)
        self.view.addSubview(self.emptyLabel)
        self.view.addSubview(self.loadingMoreIndicator)

        self.collectionView.translatesAutoresizingMaskIntoConstraints = false
        self.activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        self.emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        self.loadingMoreIndicator.translatesAutoresizingMaskIntoConstraints = false

        // Room for the loading indicator. Set once, so the grid never shifts when it comes and goes.
        self.collectionView.contentInset.bottom = Self.loadingMoreIndicatorHeight

        NSLayoutConstraint.activate([
            self.collectionView.topAnchor.constraint(equalTo: self.view.topAnchor),
            self.collectionView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            self.collectionView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.collectionView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),

            self.activityIndicator.centerXAnchor.constraint(equalTo: self.collectionView.centerXAnchor),
            self.activityIndicator.centerYAnchor.constraint(equalTo: self.collectionView.centerYAnchor),

            self.emptyLabel.centerXAnchor.constraint(equalTo: self.collectionView.centerXAnchor),
            self.emptyLabel.centerYAnchor.constraint(equalTo: self.collectionView.centerYAnchor),

            self.loadingMoreIndicator.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            self.loadingMoreIndicator.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])

        // Show trending GIFs initially
        self.reloadGifs(forTerm: "")
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        // Recompute item sizes (and therefore the column count) for the new bounds once the
        // collection view has been resized for the new orientation.
        coordinator.animate(alongsideTransition: { _ in
            self.collectionView.collectionViewLayout.invalidateLayout()
        })
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // The load task retains this view controller and its downloads are of no use once the picker
        // is gone – including when it was dismissed by swiping the sheet down.
        guard self.isBeingDismissed || self.navigationController?.isBeingDismissed == true else { return }

        self.searchDebounceWorkItem?.cancel()
        self.loadTask?.cancel()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()

        // The layout insets the items away from the horizontal safe area, which can change without
        // the width changing (and therefore without the layout invalidating itself).
        self.collectionView.collectionViewLayout.invalidateLayout()
    }

    @objc func cancelButtonPressed() {
        self.dismissPicker()
    }

    /// Dismisses the picker itself.
    ///
    /// While the search is active the search controller is presented *by* this view controller, so
    /// `self.dismiss()` would dismiss that instead of the picker, requiring a second tap. Dismissing
    /// from the presenting view controller closes the whole chain regardless.
    private func dismissPicker() {
        self.searchController.searchBar.resignFirstResponder()
        (self.presentingViewController ?? self).dismiss(animated: true)
    }

    private func searchTermDidChange(to term: String) {
        // Also called when the search is (de)activated without an actual text change
        guard term != self.currentTerm else { return }

        self.searchDebounceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.reloadGifs(forTerm: term)
        }

        self.searchDebounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + self.searchDebounceInterval, execute: workItem)
    }

    // MARK: - Loading

    private func reloadGifs(forTerm term: String) {
        self.loadTask?.cancel()

        self.generation += 1
        self.currentTerm = term
        self.cursor = 0
        self.hasMore = true
        self.isLoading = false
        self.emptyLabel.isHidden = true

        // Emptying with reloadData() would only be applied at the next layout pass, by which time the
        // new search's GIFs have been appended: the pending reload already counts them and inserting
        // on top double-counts them ("Invalid batch updates detected"). A delete keeps counts exact.
        let removedIndexPaths = (0..<self.items.count).map { IndexPath(item: $0, section: 0) }
        self.items = []
        self.updateLoadingMoreIndicator()

        if !removedIndexPaths.isEmpty {
            // Without suppressing the animation the old GIFs fade out one by one and the scroll offset
            // animates all the way back up as the content collapses. New results just start at the top.
            UIView.performWithoutAnimation {
                self.collectionView.deleteItems(at: removedIndexPaths)
                self.collectionView.setContentOffset(CGPoint(x: 0, y: -self.collectionView.adjustedContentInset.top), animated: false)
            }
        }

        self.loadMoreGifs()
    }

    /// Requests the next page once the grid is scrolled close to its end.
    ///
    /// Driven by the scroll offset rather than the last cell being displayed: GIFs are appended as they
    /// arrive, so a page's last cells are usually displayed by the time it finishes – no further
    /// `willDisplay` would arrive and the grid would silently stop growing.
    private func loadMoreGifsIfNearBottom() {
        guard self.hasMore, !self.isLoading, !self.items.isEmpty else { return }

        // Keep roughly one screen of GIFs ahead of the user
        guard self.distanceToBottom < self.collectionView.bounds.height else { return }

        self.loadMoreGifs()
    }

    /// How far the grid can still be scrolled down, i.e. 0 once it is scrolled all the way to the end.
    private var distanceToBottom: CGFloat {
        let maximumOffset = self.collectionView.contentSize.height - self.collectionView.bounds.height + self.collectionView.adjustedContentInset.bottom

        return maximumOffset - self.collectionView.contentOffset.y
    }

    private func loadMoreGifs() {
        guard self.hasMore, !self.isLoading else { return }

        let myGeneration = self.generation
        let term = self.currentTerm
        let requestedCursor = self.cursor

        self.isLoading = true
        self.updateLoadingMoreIndicator()

        // Only show the centered spinner if there are no GIFs yet – a pagination load appends below
        // what is on screen and uses the bottom indicator instead.
        if self.items.isEmpty {
            self.activityIndicator.startAnimating()
        }

        self.loadTask = Task { @MainActor in
            defer {
                // Only the active request may clear the loading state; stale requests
                // (whose generation no longer matches) must not interfere.
                if myGeneration == self.generation {
                    self.isLoading = false
                    self.activityIndicator.stopAnimating()
                    self.updateLoadingMoreIndicator()

                    // The page may not have filled the screen, or the user may be sitting at the bottom
                    // without scrolling – nothing else would then ask for the next page.
                    self.loadMoreGifsIfNearBottom()
                }
            }

            do {
                let result: NCAPIController.GiphyResult
                if term.isEmpty {
                    result = try await NCAPIController.sharedInstance().getGiphyTrending(forAccount: self.account, cursor: requestedCursor, limit: self.pageLimit)
                } else {
                    result = try await NCAPIController.sharedInstance().searchGiphy(forAccount: self.account, term: term, cursor: requestedCursor, limit: self.pageLimit)
                }

                // Ignore results if the query changed while the request was in flight
                guard !Task.isCancelled, myGeneration == self.generation else { return }

                self.cursor = result.cursor
                self.hasMore = result.gifs.count >= self.pageLimit

                await self.appendProgressively(result.gifs, generation: myGeneration)

                guard myGeneration == self.generation else { return }

                // The last page may not have added any GIF at all, so not only updated alongside an insert
                self.updateLoadingMoreIndicator()
                self.emptyLabel.isHidden = !self.items.isEmpty
            } catch {
                guard !Task.isCancelled, myGeneration == self.generation else { return }
                self.hasMore = false
                self.updateLoadingMoreIndicator()
                self.emptyLabel.isHidden = !self.items.isEmpty
            }
        }
    }

    /// Spins the bottom indicator when someone waiting at the end of the grid has more GIFs coming.
    ///
    /// Not for the initial load (the centered spinner covers that), and not while a page loads that the
    /// user hasn't scrolled to. Showing and hiding never moves anything, as its space is always reserved.
    private func updateLoadingMoreIndicator() {
        let showsIndicator = self.isLoading && !self.items.isEmpty && self.distanceToBottom < Self.loadingMoreIndicatorHeight

        if showsIndicator {
            self.loadingMoreIndicator.startAnimating()
        } else {
            self.loadingMoreIndicator.stopAnimating()
        }
    }

    /// Appends each GIF as soon as its thumbnail has arrived, so the grid fills continuously instead
    /// of a whole page appearing at once.
    ///
    /// Appended in load order, not API order: keeping API order would let one slow GIF hold back
    /// everything behind it. Appending never moves already placed items, so this only ever adds to the
    /// bottom. All requests are started at once – `SDWebImageDownloader` caps itself at 6 in parallel.
    private func appendProgressively(_ gifs: [GiphyGif], generation: Int) async {
        // NCDatabaseManager hands out unmanaged TalkAccount copies, usable off the main thread
        let account = self.account

        await withTaskGroup(of: (gif: GiphyGif, aspectRatio: CGFloat?).self) { group in
            for gif in gifs {
                group.addTask {
                    // Loading also caches, so the cell displaying it afterwards doesn't download it again
                    let image = try? await NCAPIController.sharedInstance().getGiphyGifImage(forAccount: account, url: gif.thumbnailUrl)

                    guard let size = image?.size, size.width > 0, size.height > 0 else { return (gif: gif, aspectRatio: nil) }

                    return (gif: gif, aspectRatio: size.width / size.height)
                }
            }

            for await result in group {
                // A new search started (or the picker went away): stop placing GIFs, but keep draining
                // the group so the running downloads are still awaited
                guard !Task.isCancelled, generation == self.generation else {
                    group.cancelAll()
                    continue
                }

                self.items.append(GridItem(gif: result.gif, aspectRatio: result.aspectRatio ?? Self.fallbackAspectRatio))

                self.activityIndicator.stopAnimating()
                self.collectionView.insertItems(at: [IndexPath(item: self.items.count - 1, section: 0)])
                self.updateLoadingMoreIndicator()
            }
        }
    }
}

// MARK: - Search

extension GiphyPickerViewController: UISearchResultsUpdating, UISearchBarDelegate {

    func updateSearchResults(for searchController: UISearchController) {
        let term = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.searchTermDidChange(to: term)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

// MARK: - UICollectionView

extension GiphyPickerViewController: UICollectionViewDataSource, UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: GiphyGifCell.identifier, for: indexPath)

        guard let gifCell = cell as? GiphyGifCell, indexPath.item < self.items.count else { return cell }

        // Normally still cached from measuring the GIF; an evicted one is loaded again in the
        // background. The aspect ratio is known either way, so the layout never changes.
        gifCell.setGif(self.items[indexPath.item].gif, context: self.imageContext)

        return cell
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        self.loadMoreGifsIfNearBottom()

        // Scrolling changes whether the user is waiting at the end of the grid
        self.updateLoadingMoreIndicator()
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard indexPath.item < self.items.count else { return }

        let gif = self.items[indexPath.item].gif
        self.delegate?.giphyPickerViewController(self, didSelectGifWithUrl: gif.resourceUrl)
        self.dismissPicker()
    }
}

// MARK: - GiphyWaterfallLayoutDelegate

extension GiphyPickerViewController: GiphyWaterfallLayoutDelegate {

    func waterfallLayout(_ layout: GiphyWaterfallLayout, aspectRatioForItemAt index: Int) -> CGFloat {
        guard index < self.items.count else { return Self.fallbackAspectRatio }

        return self.items[index].aspectRatio
    }
}
