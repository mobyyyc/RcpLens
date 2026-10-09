import SwiftUI
@preconcurrency import AVFoundation
import ImageIO

/// A serial queue owns all capture configuration, start/stop and photo output work.
/// The preview layer only reads the session; UI updates are delivered to the main actor.
final class ReceiptCameraDriver: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    enum Event: Sendable { case live, photo(Data), failed(String) }
    let session = AVCaptureSession()
    let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    private let queue = DispatchQueue(label: "Sliplet.receipt-camera", qos: .userInitiated)
    private let output = AVCapturePhotoOutput()
    private var configured = false
    private var takingPhoto = false
    private var receivedPhoto = false
    private var callback: (@MainActor @Sendable (Event) -> Void)?
    private var observers: [NSObjectProtocol] = []

    func start(_ callback: @escaping @MainActor @Sendable (Event) -> Void) {
        queue.async { [self] in
            self.callback = callback
            do {
                if !configured { try configure() }
                if !session.isRunning { session.startRunning() }
                emit(session.isRunning ? .live : .failed("The camera couldn’t start. Try again."))
            } catch { emit(.failed("The camera couldn’t start. Try again.")) }
        }
    }
    private func configure() throws {
        guard let device else { throw ImportFailure.unavailableFile }
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard session.canAddInput(input), session.canAddOutput(output) else { throw ImportFailure.unavailableFile }
        session.addInput(input); session.addOutput(output)
        if (try? device.lockForConfiguration()) != nil {
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
            device.unlockForConfiguration()
        }
        output.maxPhotoQualityPrioritization = .quality
        // Keep text sharp without requesting a 48 MP image or decoding full-size pixels in the UI.
        let dimensions = device.activeFormat.supportedMaxPhotoDimensions
        if let size = dimensions.filter({ Int64($0.width) * Int64($0.height) <= 16_000_000 })
            .max(by: { Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height) }) ?? dimensions.first {
            output.maxPhotoDimensions = size
        }
        configured = true
        for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.runtimeErrorNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { [weak self] _ in
                guard let self else { return }
                self.queue.async {
                    if self.session.isRunning { self.session.stopRunning() }
                    self.emit(.failed("Camera interrupted. Try again when the camera is available."))
                }
            })
        }
    }
    func stop() { queue.async { [self] in if session.isRunning { session.stopRunning() } } }
    func capture(angle: CGFloat) {
        queue.async { [self] in
            guard session.isRunning, !takingPhoto else { emit(.failed("The camera isn’t ready. Try again.")); return }
            takingPhoto = true; receivedPhoto = false
            if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            settings.maxPhotoDimensions = output.maxPhotoDimensions
            settings.photoQualityPrioritization = .balanced
            settings.flashMode = .off
            output.capturePhoto(with: settings, delegate: self)
        }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        queue.async { [self] in
            guard let data else { emit(.failed("The photo couldn’t be captured. Try again.")); return }
            receivedPhoto = true; emit(.photo(data))
        }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        let failed = error != nil
        queue.async { [self] in
            takingPhoto = false
            if failed && !receivedPhoto { emit(.failed("The photo couldn’t be captured. Try again.")) }
        }
    }
    private func emit(_ event: Event) {
        guard let callback else { return }
        Task { @MainActor in callback(event) }
    }
    deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }
}

@MainActor @Observable final class ReceiptCameraModel {
    enum State: Equatable { case starting, live, capturing, review, denied, restricted, unavailable, failed(String) }
    var state: State = .starting
    var preview: UIImage?
    var captureAngle: CGFloat = 90
    @ObservationIgnored let driver = ReceiptCameraDriver()
    @ObservationIgnored private var bytes: Data?
    @ObservationIgnored private var ended = false
    @ObservationIgnored private var preparing: Task<Void, Never>?
    @ObservationIgnored private var decoding: Task<Void, Never>?
    var fixture: String? {
        #if DEBUG
        if SyntheticNativePreview.enabled {
            return ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--camera-fixture=") })?.split(separator: "=").last.map(String.init)
        }
        #endif
        return nil
    }
    func prepare() {
        guard !ended else { return }
        preparing?.cancel(); state = .starting
        #if DEBUG
        if let fixture {
            switch fixture {
            case "denied": state = .denied
            case "restricted": state = .restricted
            case "unavailable": state = .unavailable
            default: state = .live
            }
            return
        }
        #endif
        guard driver.device != nil else { state = .unavailable; return }
        preparing = Task { [weak self] in
            var permission = AVCaptureDevice.authorizationStatus(for: .video)
            if permission == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .video)
                permission = AVCaptureDevice.authorizationStatus(for: .video)
            }
            guard let self, !self.ended, !Task.isCancelled else { return }
            switch permission {
            case .authorized: self.run()
            case .denied: self.state = .denied
            case .restricted: self.state = .restricted
            default: self.state = .failed("Camera access couldn’t be checked. Try again.")
            }
        }
    }
    private func run() {
        driver.start { [weak self] event in
            guard let self, !self.ended else { return }
            switch event {
            case .live: if self.state == .starting || self.state == .live { self.state = .live }
            case .photo(let data): self.checkPhoto(data)
            case .failed(let message):
                if self.state != .review { self.state = .failed(message) }
            }
        }
    }
    func capture() {
        guard state == .live, !ended else { return }
        state = .capturing
        #if DEBUG
        if fixture != nil {
            if fixture == "failure" { state = .failed("The photo couldn’t be captured. Try again.") }
            else { checkPhoto(SyntheticNativePreview.demoFixture(index: 0).0) }
            return
        }
        #endif
        driver.capture(angle: captureAngle)
    }
    private func checkPhoto(_ data: Data) {
        driver.stop()
        decoding?.cancel()
        decoding = Task { [weak self] in
            // Apply encoded orientation while downsampling only the confirmation preview.
            // Keep original JPEG bytes intact for Vision and the saved original.
            let work = Task.detached(priority: .userInitiated) { () -> CGImage? in
                guard !Task.isCancelled, data.count <= ReceiptStore.maximumAssetBytes,
                      let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
                return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1600,
                    kCGImageSourceShouldCacheImmediately: true
                ] as CFDictionary)
            }
            let image = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
            guard let self, !self.ended, !Task.isCancelled else { return }
            guard let image else { self.state = .failed("The photo couldn’t be opened. Please retake it."); return }
            self.bytes = data; self.preview = UIImage(cgImage: image); self.state = .review
        }
    }
    func retake() { bytes = nil; preview = nil; prepare() }
    func usePhoto() -> Data? {
        guard state == .review, let bytes, !ended else { return nil }
        close(clearPreview: false); return bytes
    }
    func pause() { driver.stop() }
    func resume() { if state == .live && fixture == nil && !ended { run() } }
    func close(clearPreview: Bool = true) {
        ended = true; preparing?.cancel(); decoding?.cancel(); bytes = nil
        if clearPreview { preview = nil }
        driver.stop()
    }
}

enum ReceiptCameraResult { case cancelled, existingImage, photo(Data) }

struct ReceiptCameraView: View {
    let completion: (ReceiptCameraResult) -> Void
    @State private var model = ReceiptCameraModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var systemTypeSize
    @Environment(\.accessibilityReduceTransparency) private var opaque
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if [.live, .capturing, .starting].contains(model.state) {
                ReceiptCameraPreview(driver: model.driver) { angle in
                    Task { @MainActor in if model.captureAngle != angle { model.captureAngle = angle } }
                }.ignoresSafeArea()
                #if DEBUG
                if model.fixture != nil { fictionalPreview.ignoresSafeArea().accessibilityHidden(true) }
                #endif
                LinearGradient(colors: [.black.opacity(0.65), .clear, .clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea().allowsHitTesting(false)
                VStack(spacing: 16) {
                    header("Receipt photo")
                    GeometryReader { geometry in
                        if geometry.size.width > geometry.size.height {
                            HStack(spacing: 24) {
                                receiptGuide
                                VStack(spacing: 20) {
                                    guideCaption
                                    shutter
                                }.frame(width: min(280, geometry.size.width * 0.38))
                            }.padding(.horizontal, 20).padding(.bottom, 16)
                        } else {
                            VStack(spacing: 16) {
                                receiptGuide
                                guideCaption.padding(.horizontal, 20)
                                shutter.padding(.top, 12).padding(.bottom, 20)
                            }
                        }
                    }
                }
                if model.state == .starting { ProgressView("Opening camera").padding(20).background(.regularMaterial, in: .capsule) }
            } else if model.state == .review, let preview = model.preview {
                VStack(spacing: 20) {
                    header("Check photo")
                    Image(uiImage: preview).resizable().scaledToFit().padding(.horizontal, 20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityLabel("Captured receipt photo")
                    Text("Make sure the text is sharp and nothing is cut off.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 28)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) { photoActions }.fixedSize(horizontal: true, vertical: false)
                        VStack(spacing: 12) { photoActions }
                    }.modifier(ReceiptActionBarLayout())
                }
            } else {
                VStack {
                    header("Camera")
                    Spacer(minLength: 12)
                    ContentUnavailableView {
                        Label(fallbackTitle, systemImage: "camera")
                    } description: { Text(fallbackMessage) } actions: {
                        VStack(spacing: 16) {
                            if model.state == .denied {
                                Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
                                    .buttonStyle(ReceiptProminentStyle()).accessibilityIdentifier("cameraSettings")
                            }
                            if case .failed = model.state {
                                Button("Try again", action: model.prepare).buttonStyle(ReceiptProminentStyle()).accessibilityIdentifier("cameraRetry")
                            }
                            Button("Choose an existing image") { finish(.existingImage) }
                                .buttonStyle(ReceiptSecondaryStyle()).accessibilityIdentifier("cameraExisting")
                        }
                    }
                    Spacer(minLength: 12)
                }
            }
        }
        .preferredColorScheme(.dark).tint(.white)
        #if DEBUG
        .dynamicTypeSize(SyntheticNativePreview.enabled && ProcessInfo.processInfo.arguments.contains("--t05-large-text") ? .accessibility5 : systemTypeSize)
        #endif
        .task { model.prepare() }
        .onDisappear { model.close() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { finish(.cancelled) }
            else if phase == .inactive { model.pause() }
            else if phase == .active { model.resume() }
        }
        .animation(ReceiptAccessibility.reduceMotion(reduceMotion) ? nil : .easeInOut(duration: 0.18), value: model.state)
    }
    private var receiptGuide: some View {
        GeometryReader { geometry in
            let height = max(0, geometry.size.height - 20)
            let width = max(0, min(geometry.size.width - 48, height * 0.66))
            ReceiptCameraCorners().stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .shadow(color: .black.opacity(0.5), radius: 3)
                .frame(width: width, height: height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
        }
    }
    @ViewBuilder private var guideCaption: some View {
        let caption = VStack(spacing: 5) {
            Text("Keep all four edges in view").font(.headline).fixedSize(horizontal: false, vertical: true)
            Text("Hold steady and avoid glare.").font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.multilineTextAlignment(.center).padding(14)
        if ReceiptAccessibility.reduceTransparency(opaque) {
            caption.background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 20))
        } else {
            caption.background(.regularMaterial, in: .rect(cornerRadius: 20))
        }
    }
    @ViewBuilder private var photoActions: some View {
        Button("Retake", systemImage: "arrow.counterclockwise", action: model.retake)
            .buttonStyle(ReceiptSecondaryStyle()).accessibilityIdentifier("cameraRetake")
        Button("Use photo", systemImage: "checkmark") {
            if let bytes = model.usePhoto() { completion(.photo(bytes)) }
        }.buttonStyle(ReceiptProminentStyle()).accessibilityIdentifier("cameraUse")
    }
    private func header(_ title: String) -> some View {
        HStack(spacing: 12) {
            Button { finish(.cancelled) } label: { Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)) }
                .buttonStyle(ReceiptSecondaryStyle(circular: true)).accessibilityLabel("Cancel camera").accessibilityIdentifier("cameraCancel")
            Text(title).font(.headline).frame(maxWidth: .infinity)
            Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
        }.padding(.horizontal, 20).padding(.top, 8)
    }
    private var shutter: some View {
        Button(action: model.capture) {
            ZStack {
                Circle().stroke(.white.opacity(0.9), lineWidth: 3).frame(width: 72, height: 72)
                Circle().fill(.white).frame(width: 60, height: 60)
                if model.state == .capturing { ProgressView().tint(.black) }
            }
        }.buttonStyle(.plain).disabled(model.state != .live)
            .opacity(model.state == .live || model.state == .capturing ? 1 : 0.4)
            .accessibilityLabel("Take receipt photo").accessibilityHint("Photographs the entire image; the guide does not crop it.")
            .accessibilityIdentifier("cameraShutter")
    }
    private var fallbackTitle: String {
        switch model.state {
        case .denied: "Allow camera access"
        case .restricted: "Camera access is restricted"
        case .unavailable: "No camera available"
        default: "Camera needs attention"
        }
    }
    private var fallbackMessage: String {
        switch model.state {
        case .denied: "Enable Camera for Sliplet in Settings, or import a receipt from Photos or Files."
        case .restricted: "Camera access is restricted on this device. You can still import from Photos or Files."
        case .unavailable:
            #if targetEnvironment(simulator)
            "Simulator has no camera. Import a receipt from Photos or Files, or take a photo on your iPhone."
            #else
            "A rear camera isn’t available on this device. You can still import from Photos or Files."
            #endif
        case .failed(let message): message
        default: "Choose a receipt image from Photos or Files."
        }
    }
    private func finish(_ result: ReceiptCameraResult) { model.close(clearPreview: false); completion(result) }
    #if DEBUG
    private var fictionalPreview: some View {
        ZStack {
            Color(white: 0.16)
            if let image = UIImage(data: SyntheticNativePreview.demoFixture(index: 0).0) {
                Image(uiImage: image).resizable().scaledToFit().padding(.horizontal, 70).padding(.vertical, 180)
            }
        }
    }
    #endif
}

private struct ReceiptCameraCorners: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let length: CGFloat = min(28, rect.width / 5)
        let radius: CGFloat = 10
        for (x, y, dx, dy) in [(rect.minX, rect.minY, 1.0, 1.0), (rect.maxX, rect.minY, -1.0, 1.0),
                                (rect.minX, rect.maxY, 1.0, -1.0), (rect.maxX, rect.maxY, -1.0, -1.0)] {
            path.move(to: CGPoint(x: x, y: y + dy * length))
            path.addLine(to: CGPoint(x: x, y: y + dy * radius))
            path.addQuadCurve(to: CGPoint(x: x + dx * radius, y: y), control: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x + dx * length, y: y))
        }
        return path
    }
}

private struct ReceiptCameraPreview: UIViewRepresentable {
    let driver: ReceiptCameraDriver
    let angleChanged: (CGFloat) -> Void
    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.previewLayer.session = driver.session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.angleChanged = angleChanged
        if let device = driver.device {
            view.rotation = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: view.previewLayer)
            view.observation = view.rotation?.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak view] _, _ in
                Task { @MainActor in view?.applyRotation() }
            }
        }
        view.captureObservation = view.rotation?.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { [weak view] _, _ in
            Task { @MainActor in view?.applyRotation() }
        }
        return view
    }
    func updateUIView(_ view: CameraPreviewView, context: Context) { view.applyRotation() }
    static func dismantleUIView(_ view: CameraPreviewView, coordinator: ()) {
        view.observation?.invalidate(); view.captureObservation?.invalidate(); view.previewLayer.session = nil
    }
}

@MainActor private final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var rotation: AVCaptureDevice.RotationCoordinator?
    var observation: NSKeyValueObservation?
    var captureObservation: NSKeyValueObservation?
    var angleChanged: ((CGFloat) -> Void)?
    override func layoutSubviews() { super.layoutSubviews(); applyRotation() }
    func applyRotation() {
        guard let rotation else { return }
        let angle = rotation.videoRotationAngleForHorizonLevelPreview
        if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
        angleChanged?(rotation.videoRotationAngleForHorizonLevelCapture)
    }
}
