//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import WebRTC

// Video of the participant sharing their screen, shown on top of the presented screen share
class CallPresenterView: UIView {

    let videoRenderView = RTCMTLVideoView(frame: .zero)

    var onCollapsedChanged: ((Bool) -> Void)?

    private(set) var isCollapsed = false

    private let avatarImageView = AvatarImageView(frame: .zero)
    private var isVideoDisabled = true
    private var expandedConstraints: [NSLayoutConstraint] = []
    private var collapsedConstraints: [NSLayoutConstraint] = []

    private let collapsedSize: CGFloat = 44
    private var isSpeaking = false

    override init(frame: CGRect) {
        super.init(frame: frame)

        // Transparent, so nothing shows around the avatar, e.g. while collapsing
        self.translatesAutoresizingMaskIntoConstraints = false
        self.backgroundColor = .clear
        self.clipsToBounds = true
        self.layer.borderColor = UIColor.white.cgColor

        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.clipsToBounds = true

        // Otherwise the intrinsic size of the downloaded avatar image grows the whole view
        avatarImageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        avatarImageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        avatarImageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        avatarImageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        self.addSubview(avatarImageView)

        // Above the avatar, which then shows through until the first video frame is rendered
        videoRenderView.videoContentMode = .scaleAspectFill
        videoRenderView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(videoRenderView)

        NSLayoutConstraint.activate([
            avatarImageView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            avatarImageView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            avatarImageView.topAnchor.constraint(equalTo: self.topAnchor),
            avatarImageView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            videoRenderView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            videoRenderView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            videoRenderView.topAnchor.constraint(equalTo: self.topAnchor),
            videoRenderView.bottomAnchor.constraint(equalTo: self.bottomAnchor)
        ])

        self.isAccessibilityElement = true
        self.accessibilityTraits = .button

        self.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggleCollapsed)))
        self.updateContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()

        NSLayoutConstraint.deactivate(expandedConstraints + collapsedConstraints)

        guard let superview else { return }

        // Same as the presenter overlay of the web client: clamp(100px, 10cqw, 242px)
        let expandedWidth = self.widthAnchor.constraint(equalTo: superview.widthAnchor, multiplier: 0.1)
        // Only the clamp may override it
        expandedWidth.priority = .required - 1

        expandedConstraints = [
            expandedWidth,
            self.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
            self.widthAnchor.constraint(lessThanOrEqualToConstant: 242),
            self.heightAnchor.constraint(equalTo: self.widthAnchor)
        ]

        collapsedConstraints = [
            self.widthAnchor.constraint(equalToConstant: collapsedSize),
            self.heightAnchor.constraint(equalToConstant: collapsedSize)
        ]

        NSLayoutConstraint.activate(isCollapsed ? collapsedConstraints : expandedConstraints)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        self.layer.cornerRadius = bounds.height / 2
    }

    func setVideoDisabled(_ disabled: Bool) {
        isVideoDisabled = disabled
        self.updateContent()
    }

    func setSpeaking(_ speaking: Bool) {
        isSpeaking = speaking
        self.updateContent()
    }

    func setAvatar(for actor: TalkActor, using account: TalkAccount) {
        avatarImageView.setActorAvatar(forId: actor.id, withType: actor.type, withDisplayName: actor.displayName, withRoomToken: nil, using: account)
        self.accessibilityLabel = String(format: NSLocalizedString("Video of %@", comment: "Accessibility label of the presenter video shown during a screen share"), actor.displayName)
    }

    func setCollapsed(_ collapsed: Bool, animated: Bool) {
        guard collapsed != isCollapsed else { return }

        isCollapsed = collapsed

        if superview != nil {
            NSLayoutConstraint.deactivate(collapsed ? expandedConstraints : collapsedConstraints)
            NSLayoutConstraint.activate(collapsed ? collapsedConstraints : expandedConstraints)
        }

        self.updateContent()

        guard animated else { return }

        UIView.animate(withDuration: 0.25) {
            self.superview?.layoutIfNeeded()
        }
    }

    @objc private func toggleCollapsed() {
        self.setCollapsed(!isCollapsed, animated: true)
        onCollapsedChanged?(isCollapsed)
    }

    private func updateContent() {
        // Collapsed, only the avatar is shown, so the presenter video can be blocked meanwhile
        let showsVideo = !isVideoDisabled && !isCollapsed

        videoRenderView.isHidden = !showsVideo
        self.layer.borderWidth = isSpeaking && !isCollapsed ? 2 : 0

        self.accessibilityHint = isCollapsed ?
            NSLocalizedString("Double tap to show the video of the presenter", comment: "") :
            NSLocalizedString("Double tap to minimize the video of the presenter", comment: "")
    }
}
