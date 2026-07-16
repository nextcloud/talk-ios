//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import AVKit
import Foundation
import UIKit
import WebRTC

// Renders remote RTCVideoFrames into an AVSampleBufferDisplayLayer.
// Metal (RTCMTLVideoView) is not allowed to render while the app is in the background,
// AVSampleBufferDisplayLayer is, which makes it the only way to show remote video
// in the Picture in Picture window.
class SampleBufferVideoRenderView: UIView, RTCVideoRenderer {

    private class DisplayLayerView: UIView {
        override class var layerClass: AnyClass {
            return AVSampleBufferDisplayLayer.self
        }

        var sampleBufferLayer: AVSampleBufferDisplayLayer {
            // swiftlint:disable:next force_cast
            return layer as! AVSampleBufferDisplayLayer
        }
    }

    // Called on the main queue whenever the (rotated) size of the rendered video changes
    public var onVideoSizeChanged: ((CGSize) -> Void)?

    // Mirrors the rendered video, as it is expected for the own video of the front camera
    public var isMirrored = false {
        didSet {
            guard isMirrored != oldValue else { return }

            DispatchQueue.main.async {
                self.transform = self.isMirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity
            }
        }
    }

    private let displayView = DisplayLayerView()
    private var videoRotation = RTCVideoRotation._0

    // The (rotated) size of the currently rendered video
    public private(set) var videoSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)

        displayView.sampleBufferLayer.videoGravity = .resizeAspect
        self.addSubview(displayView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.layoutDisplayView()
    }

    // The frames of the sample buffer layer are not rotated, so the rotation
    // of the video frames is applied as a transform on the layer's view
    private func layoutDisplayView() {
        let isRotatedSideways = videoRotation == ._90 || videoRotation == ._270

        displayView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        displayView.bounds = isRotatedSideways ? CGRect(x: 0, y: 0, width: bounds.height, height: bounds.width) : bounds

        switch videoRotation {
        case ._90:
            displayView.transform = CGAffineTransform(rotationAngle: .pi / 2)
        case ._180:
            displayView.transform = CGAffineTransform(rotationAngle: .pi)
        case ._270:
            displayView.transform = CGAffineTransform(rotationAngle: -.pi / 2)
        default:
            displayView.transform = .identity
        }
    }

    public func flush() {
        DispatchQueue.main.async {
            self.displayView.sampleBufferLayer.flushAndRemoveImage()
        }
    }

    // MARK: - RTCVideoRenderer

    public func setSize(_ size: CGSize) {
        // The size reported here does not include the frame rotation,
        // so the rotated size is determined in renderFrame instead
    }

    public func renderFrame(_ frame: RTCVideoFrame?) {
        // Called on the WebRTC decoding thread
        guard let frame,
              let pixelBuffer = Self.pixelBuffer(from: frame.buffer),
              let sampleBuffer = Self.sampleBuffer(from: pixelBuffer)
        else { return }

        let rotation = frame.rotation
        var size = CGSize(width: CGFloat(frame.width), height: CGFloat(frame.height))

        if rotation == ._90 || rotation == ._270 {
            size = CGSize(width: size.height, height: size.width)
        }

        DispatchQueue.main.async {
            if self.displayView.sampleBufferLayer.status == .failed {
                self.displayView.sampleBufferLayer.flush()
            }

            if rotation != self.videoRotation {
                self.videoRotation = rotation

                UIView.animate(withDuration: 0.3) {
                    self.layoutDisplayView()
                }
            }

            if size != self.videoSize {
                self.videoSize = size
                self.onVideoSizeChanged?(size)
            }

            self.displayView.sampleBufferLayer.enqueue(sampleBuffer)
        }
    }

    // MARK: - Frame conversion

    private static func pixelBuffer(from buffer: RTCVideoFrameBuffer) -> CVPixelBuffer? {
        // Hardware decoded frames are already backed by a CVPixelBuffer
        if let cvPixelBuffer = buffer as? RTCCVPixelBuffer {
            return cvPixelBuffer.pixelBuffer
        }

        // Software decoded frames (e.g. VP8) need to be converted to a NV12 CVPixelBuffer
        return self.nv12PixelBuffer(from: buffer.toI420())
    }

    private static func nv12PixelBuffer(from i420Buffer: RTCYUVPlanarBuffer) -> CVPixelBuffer? {
        let width = Int(i420Buffer.width)
        let height = Int(i420Buffer.height)
        let attributes: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [String: Any]()]
        var pixelBufferOut: CVPixelBuffer?

        let result = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, attributes as CFDictionary, &pixelBufferOut)
        guard result == kCVReturnSuccess, let pixelBuffer = pixelBufferOut else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let lumaBaseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
              let chromaBaseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)
        else { return nil }

        // Copy the luma plane row by row, as the strides might differ
        let lumaDestination = lumaBaseAddress.assumingMemoryBound(to: UInt8.self)
        let lumaDestinationStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let lumaSourceStride = Int(i420Buffer.strideY)

        for row in 0..<height {
            memcpy(lumaDestination + row * lumaDestinationStride, i420Buffer.dataY + row * lumaSourceStride, width)
        }

        // Interleave the U and V planes into the NV12 chroma plane
        let chromaDestination = chromaBaseAddress.assumingMemoryBound(to: UInt8.self)
        let chromaDestinationStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
        let chromaWidth = Int(i420Buffer.chromaWidth)
        let chromaHeight = Int(i420Buffer.chromaHeight)

        for row in 0..<chromaHeight {
            let destinationRow = chromaDestination + row * chromaDestinationStride
            let uSourceRow = i420Buffer.dataU + row * Int(i420Buffer.strideU)
            let vSourceRow = i420Buffer.dataV + row * Int(i420Buffer.strideV)

            for column in 0..<chromaWidth {
                destinationRow[column * 2] = uSourceRow[column]
                destinationRow[column * 2 + 1] = vSourceRow[column]
            }
        }

        return pixelBuffer
    }

    private static func sampleBuffer(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        var formatDescriptionOut: CMVideoFormatDescription?

        let formatResult = CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &formatDescriptionOut)
        guard formatResult == noErr, let formatDescription = formatDescriptionOut else { return nil }

        var timingInfo = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
        var sampleBufferOut: CMSampleBuffer?

        let sampleResult = CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
                                                                    imageBuffer: pixelBuffer,
                                                                    formatDescription: formatDescription,
                                                                    sampleTiming: &timingInfo,
                                                                    sampleBufferOut: &sampleBufferOut)
        guard sampleResult == noErr, let sampleBuffer = sampleBufferOut else { return nil }

        // Make sure the frame is displayed as soon as it is enqueued
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true), CFArrayGetCount(attachments) > 0 {
            let attachment = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(attachment,
                                 Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }

        return sampleBuffer
    }
}

// Content view controller of the Picture in Picture window. Shows the video of the
// promoted participant, or the avatar and name when no video is available.
class CallPiPViewController: AVPictureInPictureVideoCallViewController {

    public let videoRenderView = SampleBufferVideoRenderView()
    public let localVideoRenderView = SampleBufferVideoRenderView()

    private let placeholderView = UIView()
    private let avatarImageView = AvatarImageView(frame: .zero)
    private let displayNameLabel = UILabel()

    private var localVideoAspectConstraint: NSLayoutConstraint?
    private var localVideoLandscapeSizeConstraint: NSLayoutConstraint?
    private var localVideoPortraitSizeConstraint: NSLayoutConstraint?

    private let avatarSize = 80.0

    init() {
        super.init(nibName: nil, bundle: nil)

        self.preferredContentSize = CGSize(width: 1280, height: 720)

        // Hide here instead of in viewDidLoad: when Picture in Picture starts for the first
        // time, the own video might be unhidden by the delegate before the view is loaded,
        // in that case viewDidLoad would override the visibility again
        self.localVideoRenderView.isHidden = true

        // The size handlers are also set up here: the first video frames can arrive before
        // the view is loaded and the callback only fires when the reported size changes,
        // so a closure assigned in viewDidLoad would miss the initial size
        videoRenderView.onVideoSizeChanged = { [weak self] size in
            self?.setVideoContentSize(size)
        }

        localVideoRenderView.onVideoSizeChanged = { [weak self] size in
            self?.updateLocalVideoAspectRatio(size)
        }

        AllocationTracker.shared.addAllocation("CallPiPViewController")
    }

    deinit {
        AllocationTracker.shared.removeAllocation("CallPiPViewController")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = .black

        videoRenderView.translatesAutoresizingMaskIntoConstraints = false
        localVideoRenderView.translatesAutoresizingMaskIntoConstraints = false
        placeholderView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        displayNameLabel.translatesAutoresizingMaskIntoConstraints = false

        localVideoRenderView.layer.cornerRadius = 8
        localVideoRenderView.layer.masksToBounds = true

        avatarImageView.layer.cornerRadius = avatarSize / 2
        avatarImageView.layer.masksToBounds = true

        displayNameLabel.textColor = .white
        displayNameLabel.textAlignment = .center
        displayNameLabel.font = .preferredFont(forTextStyle: .callout)

        placeholderView.addSubview(avatarImageView)
        placeholderView.addSubview(displayNameLabel)

        self.view.addSubview(videoRenderView)
        self.view.addSubview(placeholderView)
        self.view.addSubview(localVideoRenderView)

        // The aspect constraint might already exist when the own video reported a size
        // before the view was loaded
        let localVideoAspectConstraint = self.localVideoAspectConstraint ?? localVideoRenderView.heightAnchor.constraint(equalTo: localVideoRenderView.widthAnchor, multiplier: 4.0 / 3.0)
        self.localVideoAspectConstraint = localVideoAspectConstraint

        // The window aspect follows the remote video (via preferredContentSize), so size the
        // own video relative to the longer side of the window, to get a consistent size for
        // both portrait and landscape remote videos. The two constraints are switched in
        // viewDidLayoutSubviews based on the current window size
        let localVideoLandscapeSizeConstraint = localVideoRenderView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.2)
        let localVideoPortraitSizeConstraint = localVideoRenderView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.2)
        self.localVideoLandscapeSizeConstraint = localVideoLandscapeSizeConstraint
        self.localVideoPortraitSizeConstraint = localVideoPortraitSizeConstraint

        NSLayoutConstraint.activate([
            localVideoAspectConstraint,
            localVideoLandscapeSizeConstraint,
            localVideoRenderView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            localVideoRenderView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),

            videoRenderView.topAnchor.constraint(equalTo: view.topAnchor),
            videoRenderView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            videoRenderView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoRenderView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            placeholderView.topAnchor.constraint(equalTo: view.topAnchor),
            placeholderView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            placeholderView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            placeholderView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            avatarImageView.centerXAnchor.constraint(equalTo: placeholderView.centerXAnchor),
            avatarImageView.centerYAnchor.constraint(equalTo: placeholderView.centerYAnchor, constant: -12),
            avatarImageView.widthAnchor.constraint(equalToConstant: avatarSize),
            avatarImageView.heightAnchor.constraint(equalToConstant: avatarSize),

            displayNameLabel.topAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: 8),
            displayNameLabel.leadingAnchor.constraint(greaterThanOrEqualTo: placeholderView.leadingAnchor, constant: 8),
            displayNameLabel.trailingAnchor.constraint(lessThanOrEqualTo: placeholderView.trailingAnchor, constant: -8),
            displayNameLabel.centerXAnchor.constraint(equalTo: placeholderView.centerXAnchor)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.updateLocalVideoSizeConstraint()
    }

    private func updateLocalVideoSizeConstraint() {
        guard let localVideoLandscapeSizeConstraint, let localVideoPortraitSizeConstraint else { return }

        let isWindowLandscape = view.bounds.width >= view.bounds.height

        // Always deactivate first, so both constraints are never active at the same time
        if isWindowLandscape {
            localVideoPortraitSizeConstraint.isActive = false
            localVideoLandscapeSizeConstraint.isActive = true
        } else {
            localVideoLandscapeSizeConstraint.isActive = false
            localVideoPortraitSizeConstraint.isActive = true
        }
    }

    // Match the aspect ratio of the own video view to the (rotated) size of the
    // rendered video, so the video is not letterboxed inside its corner frame
    private func updateLocalVideoAspectRatio(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }

        localVideoAspectConstraint?.isActive = false

        let aspectConstraint = localVideoRenderView.heightAnchor.constraint(equalTo: localVideoRenderView.widthAnchor, multiplier: size.height / size.width)
        aspectConstraint.isActive = true

        localVideoAspectConstraint = aspectConstraint

        // Animate the size change when the own video is already visible
        if viewIfLoaded?.window != nil {
            UIView.animate(withDuration: 0.3) {
                self.view.layoutIfNeeded()
            }
        }
    }

    // The size is normalized to a fixed dimension, so the window size only depends on the
    // aspect ratio of the video and not on the resolution of the stream, which usually
    // starts low and adapts shortly after the stream was established
    private static func normalizedContentSize(for videoSize: CGSize) -> CGSize? {
        guard videoSize.width > 0, videoSize.height > 0 else { return nil }

        let scale = 1280 / max(videoSize.width, videoSize.height)

        return CGSize(width: (videoSize.width * scale).rounded(), height: (videoSize.height * scale).rounded())
    }

    // Sets the preferred content size of the Picture in Picture window from a video size.
    // Note that the window resize is performed by AVKit without an animation, there is
    // no API to influence that
    public func setVideoContentSize(_ size: CGSize) {
        guard let normalizedSize = Self.normalizedContentSize(for: size),
              normalizedSize != self.preferredContentSize
        else { return }

        self.preferredContentSize = normalizedSize
    }

    // Re-assert the size of the currently rendered video: AVKit ignores changes to
    // preferredContentSize while the Picture in Picture window is still animating in,
    // so the setter needs to be called again even though the value did not change
    public func reassertVideoContentSize() {
        guard let normalizedSize = Self.normalizedContentSize(for: videoRenderView.videoSize) else { return }

        self.preferredContentSize = normalizedSize
    }

    public func setVideoDisabled(_ disabled: Bool) {
        placeholderView.isHidden = !disabled
        videoRenderView.isHidden = disabled
    }

    public func setLocalVideoHidden(_ hidden: Bool) {
        localVideoRenderView.isHidden = hidden
    }

    public func setAvatar(for actor: TalkActor, using account: TalkAccount) {
        avatarImageView.isHidden = false
        avatarImageView.setActorAvatar(forId: actor.id, withType: actor.type, withDisplayName: actor.displayName, withRoomToken: nil, using: account)
        displayNameLabel.text = actor.displayName
    }

    public func showPlaceholder(withDisplayName displayName: String?) {
        avatarImageView.isHidden = true
        displayNameLabel.text = displayName

        self.setVideoDisabled(true)
    }
}
