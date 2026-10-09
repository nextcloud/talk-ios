//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import AVFoundation
import UIKit
import WebRTC

let kCallParticipantCellIdentifier = "CallParticipantCellIdentifier"
let kCallParticipantCellNibName = "CallParticipantViewCell"
let kCallParticipantCellMinHeight: CGFloat = 128

protocol CallParticipantViewCellDelegate: AnyObject {
    func cellWants(toPresentScreenSharing participantCell: CallParticipantViewCell)
    func cellWants(toChangeZoom participantCell: CallParticipantViewCell, showOriginalSize: Bool)
}

class CallParticipantViewCell: UICollectionViewCell {

    weak var actionsDelegate: CallParticipantViewCellDelegate?

    var peerIdentifier: String?
    var showOriginalSize = false

    private var peerDisplayName: String?

    var displayName: String? {
        get { peerDisplayName }
        set {
            peerDisplayName = (newValue?.isEmpty ?? true) ? NSLocalizedString("Guest", comment: "") : newValue

            guard peerNameLabel.text != peerDisplayName else { return }

            DispatchQueue.main.async {
                self.peerNameLabel.text = self.peerDisplayName
            }
        }
    }

    var audioDisabled = false {
        didSet {
            DispatchQueue.main.async {
                self.configureParticipantButtons()
            }
        }
    }

    var screenShared = false {
        didSet {
            DispatchQueue.main.async {
                self.configureParticipantButtons()
            }
        }
    }

    var videoDisabled = false {
        didSet {
            attachedVideoView?.isHidden = videoDisabled
            peerAvatarImageView.isHidden = !videoDisabled
        }
    }

    var connectionState: RTCIceConnectionState = .new {
        didSet {
            invalidateDisconnectedTimer()

            switch connectionState {
            case .disconnected:
                setDisconnectedTimer()
            case .failed:
                setFailedConnectionUI()
            case .connected, .completed:
                setConnectedUI()
            default:
                setConnectingUI()
            }
        }
    }

    var remoteVideoSize: CGSize = .zero {
        didSet {
            resizeRemoteVideoView()
            updateDebugLabel()
        }
    }

    var debugStatsText: String? {
        didSet {
            updateDebugLabel()
        }
    }

    @IBOutlet weak var peerVideoView: UIView!
    @IBOutlet weak var peerNameLabel: UILabel!
    @IBOutlet weak var activityIndicator: MDCActivityIndicator!
    @IBOutlet weak var peerAvatarImageView: AvatarImageView!
    @IBOutlet weak var audioOffIndicator: UIButton!
    @IBOutlet weak var screensharingIndicator: UIButton!
    @IBOutlet weak var raisedHandIndicator: UIButton!
    @IBOutlet weak var stackViewBottomConstraint: NSLayoutConstraint!
    @IBOutlet weak var stackViewLeftConstraint: NSLayoutConstraint!
    @IBOutlet weak var stackViewRightConstraint: NSLayoutConstraint!
    @IBOutlet weak var screensharingIndiciatorRightConstraint: NSLayoutConstraint!
    @IBOutlet weak var screensharingIndiciatorTopConstraint: NSLayoutConstraint!

    private var videoView: RTCMTLVideoView?
    private var disconnectedTimer: Timer?
    private var debugLabel: UILabel?

    // A participant's video view moves between cells, so this cell may still point to a view another cell shows now
    private var attachedVideoView: RTCMTLVideoView? {
        guard let videoView, videoView.superview == peerVideoView else { return nil }

        return videoView
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        audioOffIndicator.isHidden = true
        screensharingIndicator.isHidden = true
        raisedHandIndicator.isHidden = true

        audioOffIndicator.layer.cornerRadius = 4
        audioOffIndicator.clipsToBounds = true
        screensharingIndicator.layer.cornerRadius = 4
        screensharingIndicator.clipsToBounds = true

        activityIndicator.radius = 50
        activityIndicator.cycleColors = [.lightGray]

        peerAvatarImageView.isHidden = true
        peerAvatarImageView.layer.cornerRadius = peerAvatarImageView.bounds.width / 2
        peerAvatarImageView.layer.masksToBounds = true

        layer.cornerRadius = 22
        layer.masksToBounds = true

        // Fixed gray background instead of a username based color (see nextcloud/spreed#17047)
        backgroundColor = NCAppBranding.getDynamicColor(.systemGray, withDarkMode: .systemGray3)

        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(toggleZoom))
        tapGestureRecognizer.numberOfTapsRequired = 2
        contentView.addGestureRecognizer(tapGestureRecognizer)

        if NCUtils.isTestEnvironment {
            setupDebugLabel()
        }
    }

    // Shows the connection stats when enabled, otherwise the received video resolution, e.g. to check which simulcast layer is relayed
    private func setupDebugLabel() {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedDigitSystemFont(ofSize: UIFont.smallSystemFontSize, weight: .medium)
        label.textColor = .white
        label.backgroundColor = UIColor(white: 0, alpha: 0.5)
        label.numberOfLines = 0
        label.isHidden = true

        contentView.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -16)
        ])

        debugLabel = label
    }

    private func updateDebugLabel() {
        guard let debugLabel else { return }

        if let debugStatsText, !debugStatsText.isEmpty {
            debugLabel.text = debugStatsText
            debugLabel.isHidden = false
            return
        }

        debugLabel.text = String(format: "%.0fx%.0f", remoteVideoSize.width, remoteVideoSize.height)
        debugLabel.isHidden = remoteVideoSize == .zero
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        peerAvatarImageView.prepareForReuse()
        peerAvatarImageView.alpha = 1

        peerDisplayName = nil
        peerNameLabel.text = nil
        attachedVideoView?.removeFromSuperview()
        videoView = nil
        showOriginalSize = false
        debugStatsText = nil
        layer.borderWidth = 0
        hideLoadingSpinner()
        invalidateDisconnectedTimer()
    }

    override func apply(_ layoutAttributes: UICollectionViewLayoutAttributes) {
        super.apply(layoutAttributes)

        resizeRemoteVideoView()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Usually the padding to the side of the cell is 22 (= cornerRadius), on really small cells it's cornerRadius / 2
        let padding: CGFloat = (bounds.width <= 200 || bounds.height <= 200) ? 11 : 22

        stackViewLeftConstraint.constant = padding
        stackViewRightConstraint.constant = padding
        stackViewBottomConstraint.constant = padding
        screensharingIndiciatorTopConstraint.constant = padding
        screensharingIndiciatorRightConstraint.constant = padding

        contentView.layoutSubviews()

        peerAvatarImageView.layer.cornerRadius = peerAvatarImageView.bounds.width / 2
        activityIndicator.radius = peerAvatarImageView.bounds.width / 2
    }

    @objc private func toggleZoom() {
        showOriginalSize.toggle()
        actionsDelegate?.cellWants(toChangeZoom: self, showOriginalSize: showOriginalSize)
        resizeRemoteVideoView()
    }

    func setAvatar(for actor: TalkActor) {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        peerAvatarImageView.setActorAvatar(forId: actor.id, withType: actor.type, withDisplayName: actor.displayName, withRoomToken: nil, using: activeAccount)
    }

    func setSpeaking(_ speaking: Bool) {
        if speaking {
            layer.borderColor = UIColor.white.cgColor
            layer.borderWidth = 2
        } else {
            layer.borderWidth = 0
        }
    }

    func setRaiseHand(_ raised: Bool) {
        DispatchQueue.main.async {
            self.raisedHandIndicator.isHidden = !raised
        }
    }

    func setVideoView(_ videoView: RTCMTLVideoView) {
        DispatchQueue.main.async {
            guard videoView != self.attachedVideoView else { return }

            self.attachedVideoView?.removeFromSuperview()
            self.videoView = videoView
            self.peerVideoView.addSubview(videoView)
            videoView.isHidden = self.videoDisabled
            self.resizeRemoteVideoView()
        }
    }

    func resizeRemoteVideoView() {
        guard let attachedVideoView else { return }

        guard remoteVideoSize.width > 0, remoteVideoSize.height > 0 else {
            attachedVideoView.frame = bounds
            return
        }

        var remoteVideoFrame = AVMakeRect(aspectRatio: remoteVideoSize, insideRect: bounds)

        if !showOriginalSize {
            // Aspect fill, so the video covers the whole cell
            let scale = max(bounds.height / remoteVideoFrame.height, bounds.width / remoteVideoFrame.width)
            remoteVideoFrame.size.width *= scale
            remoteVideoFrame.size.height *= scale
        }

        attachedVideoView.frame = remoteVideoFrame
        attachedVideoView.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    // MARK: - Connection state

    private func setDisconnectedTimer() {
        disconnectedTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            self?.setDisconnectedUI()
        }
    }

    private func invalidateDisconnectedTimer() {
        disconnectedTimer?.invalidate()
        disconnectedTimer = nil
    }

    private func setDisconnectedUI() {
        guard connectionState == .disconnected else { return }

        DispatchQueue.main.async {
            self.peerNameLabel.text = String(format: NSLocalizedString("Connecting to %@ …", comment: ""), self.displayName ?? "")
            self.peerAvatarImageView.alpha = 0.3
            self.hideLoadingSpinner()
        }
    }

    private func setConnectingUI() {
        DispatchQueue.main.async {
            self.peerAvatarImageView.alpha = 0.3
            self.showLoadingSpinner()
        }
    }

    private func setFailedConnectionUI() {
        DispatchQueue.main.async {
            self.peerNameLabel.text = String(format: NSLocalizedString("Failed to connect to %@", comment: ""), self.displayName ?? "")
            self.peerAvatarImageView.alpha = 0.3
        }
    }

    private func setConnectedUI() {
        DispatchQueue.main.async {
            self.peerNameLabel.text = self.displayName
            self.peerAvatarImageView.alpha = 1
            self.hideLoadingSpinner()
        }
    }

    private func showLoadingSpinner() {
        activityIndicator.startAnimating()
        activityIndicator.isHidden = false
    }

    private func hideLoadingSpinner() {
        activityIndicator.stopAnimating()
        activityIndicator.isHidden = true
    }

    // MARK: - Participant buttons

    @IBAction func screenSharingButtonPressed(_ sender: Any) {
        actionsDelegate?.cellWants(toPresentScreenSharing: self)
    }

    private func configureParticipantButtons() {
        audioOffIndicator.isHidden = !audioDisabled
        screensharingIndicator.isHidden = !screenShared
    }
}
