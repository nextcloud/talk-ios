//
// SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

// Based on https://developer.apple.com/documentation/vision/applying_matte_effects_to_people_in_images_and_video

import Foundation
import Vision
import CoreImage.CIFilterBuiltins
import MetalKit

@objc protocol NCCameraControllerDelegate {
    @objc func didDrawFirstFrameOnLocalView()
}

@objcMembers
class NCCameraController: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, MTKViewDelegate {

    public weak var delegate: NCCameraControllerDelegate?

    // State
    private var backgroundBlurEnabled = NCUserDefaults.backgroundBlurEnabled()
    private var usingFrontCamera = true
    private var deviceOrientation: UIDeviceOrientation = UIDevice.current.orientation
    private var videoRotation: RTCVideoRotation = ._0
    private var firstLocalViewFrameDrawn = false

    // AVFoundation
    private var session: AVCaptureSession?

    // WebRTC
    private var videoSource: RTCVideoSource
    private var videoCapturer: RTCVideoCapturer
    private let framerateLimit = 30.0

    // Vision
    private let requestHandler = VNSequenceRequestHandler()
    private var segmentationRequest: VNGeneratePersonSegmentationRequest!

    // Metal
    private var metalDevice: MTLDevice!
    private var metalCommandQueue: MTLCommandQueue!

    public weak var localView: MTKView? {
        didSet {
            localView?.device = metalDevice
            localView?.isPaused = true
            localView?.enableSetNeedsDisplay = false
            localView?.delegate = self
            localView?.framebufferOnly = false
            localView?.contentMode = .scaleAspectFit
        }
    }

    // Core image
    private var context: CIContext!
    private var lastImage: CIImage?

    // MARK: - Init

    init(videoSource: RTCVideoSource, videoCapturer: RTCVideoCapturer) {
        self.videoSource = videoSource
        self.videoCapturer = videoCapturer

        super.init()

        initMetal()
        initVisionRequests()
        initAVCaptureSession()

        NotificationCenter.default.addObserver(self, selector: #selector(deviceOrientationDidChangeNotification), name: UIDevice.orientationDidChangeNotification, object: nil)
        self.updateVideoRotationBasedOnDeviceOrientation()
    }

    deinit {
        session?.stopRunning()
    }

    func initMetal() {
        metalDevice = MTLCreateSystemDefaultDevice()
        metalCommandQueue = metalDevice.makeCommandQueue()

        context = CIContext(mtlDevice: metalDevice)
    }

    func initVisionRequests() {
        // Create a request to segment a person from an image.
        segmentationRequest = VNGeneratePersonSegmentationRequest()
        segmentationRequest.qualityLevel = .balanced
        segmentationRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8
    }

    func switchCamera() {
        var newInput: AVCaptureDeviceInput

        if self.usingFrontCamera {
            newInput = getBackCameraInput()
        } else {
            newInput = getFrontCameraInput()
        }

        if let firstInput = session?.inputs.first {
            session?.removeInput(firstInput)
        }

        // Stop and restart the session to prevent a weird glitch when rotating our local view
        self.session?.stopRunning()
        self.session?.addInput(newInput)

        // We need to set the orientation again, because otherweise after switching the video is turned
        self.session?.outputs.first?.connections.first?.videoOrientation = .portrait
        self.session?.startRunning()
        self.usingFrontCamera = !self.usingFrontCamera
    }

    // See ARDCaptureController from the WebRTC project
    func getVideoFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        let settings = NCSettingsController.sharedInstance().videoSettingsModel
        let formats = RTCCameraVideoCapturer.supportedFormats(for: device)

        let targetWidth = settings?.currentVideoResolutionWidthFromStore() ?? 0
        let targetHeight = settings?.currentVideoResolutionHeightFromStore() ?? 0
        var selectedFormat: AVCaptureDevice.Format?
        var currentDiff = INT_MAX

        for format in formats {
            let dimension = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let diff = abs(targetWidth - dimension.width) + abs(targetHeight - dimension.height)

            if diff < currentDiff {
                selectedFormat = format
                currentDiff = diff
            }
        }

        return selectedFormat
    }

    // See ARDCaptureController from the WebRTC project
    func getVideoFps(for format: AVCaptureDevice.Format) -> Double {
        var maxFramerate = 0.0

        for fpsRange in format.videoSupportedFrameRateRanges {
            maxFramerate = fmax(maxFramerate, fpsRange.maxFrameRate)
        }

        return fmin(maxFramerate, framerateLimit)
    }

    func setFormat(for device: AVCaptureDevice) {
        if let format = getVideoFormat(for: device) {
            do {
                try device.lockForConfiguration()
                device.activeFormat = format

                let fps = Int32(getVideoFps(for: format))
                device.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: fps)

                device.unlockForConfiguration()
            } catch {
                print("Could not lock configuration")
            }
        }
    }

    func getFrontCameraInput() -> AVCaptureDeviceInput {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            fatalError("Error getting AVCaptureDevice.")
        }

        self.setFormat(for: device)

        guard let input = try? AVCaptureDeviceInput(device: device) else {
            fatalError("Error getting AVCaptureDeviceInput")
        }

        return input
    }

    func getBackCameraInput() -> AVCaptureDeviceInput {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            fatalError("Error getting AVCaptureDevice.")
        }

        self.setFormat(for: device)

        guard let input = try? AVCaptureDeviceInput(device: device) else {
            fatalError("Error getting AVCaptureDeviceInput")
        }

        return input
    }

    func initAVCaptureSession() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.session = AVCaptureSession()

            self.session?.sessionPreset = .inputPriority

            if self.usingFrontCamera {
                self.session?.addInput(self.getFrontCameraInput())
            } else {
                self.session?.addInput(self.getBackCameraInput())
            }

            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: .global(qos: .userInteractive))

            self.session?.addOutput(output)
            output.connections.first?.videoOrientation = .portrait
            self.session?.startRunning()
        }
    }

    public func stopAVCaptureSession() {
        self.session?.stopRunning()
    }

    // MARK: - Public switches

    public func enableBackgroundBlur(enable: Bool) {
        DispatchQueue.global(qos: .userInteractive).async {
            self.backgroundBlurEnabled = enable
            NCUserDefaults.setBackgroundBlurEnabled(enable)
        }
    }

    public func isBackgroundBlurEnabled() -> Bool {
        return self.backgroundBlurEnabled
    }

    // MARK: - Videoframe processing

    func blend(original frameImage: CIImage,
               mask maskPixelBuffer: CVPixelBuffer) -> CIImage? {

        // Create CIImage objects for the video frame and the segmentation mask.
        let originalImage = frameImage.oriented(.right)
        var maskImage = CIImage(cvPixelBuffer: maskPixelBuffer)

        // Scale the mask image to fit the bounds of the video frame.
        let scaleX = originalImage.extent.width / maskImage.extent.width
        let scaleY = originalImage.extent.height / maskImage.extent.height
        maskImage = maskImage.transformed(by: .init(scaleX: scaleX, y: scaleY))

        // Use "clampedToExtent()" to prevent black borders after applying the gaussian blur
        // Make sure to crop the image back afterwards to its original size, otherwise the result is disorted
        let backgroundImage = originalImage.clampedToExtent().applyingGaussianBlur(sigma: 8).cropped(to: originalImage.extent)

        // Blend the original, background, and mask images.
        let blendFilter = CIFilter.blendWithRedMask()
        blendFilter.inputImage = originalImage
        blendFilter.backgroundImage = backgroundImage
        blendFilter.maskImage = maskImage

        // Return the new blended image
        return blendFilter.outputImage?.oriented(.left)
    }

    func processVideoFrame(_ framePixelBuffer: CVPixelBuffer, _ sampleBuffer: CMSampleBuffer) {
        let pixelBuffer = framePixelBuffer
        var frameImage = CIImage(cvPixelBuffer: framePixelBuffer)

        if self.backgroundBlurEnabled {
            // Perform the requests on the pixel buffer that contains the video frame.
            try? requestHandler.perform([segmentationRequest],
                                        on: pixelBuffer,
                                        orientation: .right)

            // Get the pixel buffer that contains the mask image.
            guard let maskPixelBuffer = segmentationRequest.results?.first?.pixelBuffer else {
                return
            }

            // Process the images.
            if let newImage = blend(original: frameImage, mask: maskPixelBuffer) {
                context.render(newImage, to: pixelBuffer)
                frameImage = newImage
            }
        }

        self.lastImage = frameImage

        if let localView {
            localView.draw()

            if !self.firstLocalViewFrameDrawn {
                self.delegate?.didDrawFirstFrameOnLocalView()
                self.firstLocalViewFrameDrawn = true
            }
        }

        // Create the RTCVideoFrame
        let timeStampNs =  CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * Float64(NSEC_PER_SEC)
        let rtcpixelBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
        let videoFrame: RTCVideoFrame? = RTCVideoFrame(buffer: rtcpixelBuffer, rotation: videoRotation, timeStampNs: Int64(timeStampNs))

        if let videoFrame = videoFrame {
            self.videoSource.capturer(self.videoCapturer, didCapture: videoFrame)
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = sampleBuffer.imageBuffer else {
            return
        }

        self.processVideoFrame(pixelBuffer, sampleBuffer)
    }

    // MARK: - MTKViewDelegate

    func draw(in view: MTKView) {
        guard let commandBuffer = metalCommandQueue.makeCommandBuffer(),
              let currentDrawable = view.currentDrawable,
              let localView = localView,
              var ciImage = lastImage else {
            return
        }

        // Correctly rotate the local image
        if videoRotation == ._180 {
            ciImage = ciImage.oriented(.down)
        } else if videoRotation == ._90 {
            ciImage = ciImage.oriented(.right)
        } else if videoRotation == ._270 {
            ciImage = ciImage.oriented(.left)
        }

        // make sure the image is full screen
        let drawSize = localView.drawableSize
        let scaleX = drawSize.width / ciImage.extent.width
        let scaleY = drawSize.height / ciImage.extent.height

        var scale = scaleX

        // Make sure we use the smaller scale
        if scaleY < scaleX {
            scale = scaleY
        }

        // Make sure to scale by keeping the aspect ratio
        let newImage = ciImage.transformed(by: .init(scaleX: scale, y: scale))

        // render into the metal texture
        self.context.render(newImage,
                              to: currentDrawable.texture,
                              commandBuffer: commandBuffer,
                              bounds: newImage.extent,
                              colorSpace: CGColorSpaceCreateDeviceRGB())

        // register drawwable to command buffer
        commandBuffer.present(currentDrawable)
        commandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Delegate method not implemented.
    }

    // MARK: - Notifications

    func deviceOrientationDidChangeNotification() {
        self.deviceOrientation = UIDevice.current.orientation
        self.updateVideoRotationBasedOnDeviceOrientation()
    }

    func updateVideoRotationBasedOnDeviceOrientation() {
        // Handle video rotation based on device orientation
        if deviceOrientation == .portrait {
            videoRotation = ._0
        } else if deviceOrientation == .portraitUpsideDown {
            videoRotation = ._180
        } else if deviceOrientation == .landscapeRight {
            videoRotation = usingFrontCamera ? ._270 : ._90
        } else if deviceOrientation == .landscapeLeft {
            videoRotation = usingFrontCamera ? ._90 : ._270
        }
    }
}
