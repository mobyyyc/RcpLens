import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// System out-of-process picker. Only the selected image is made available; no library permission request.
struct ReceiptPhotoPicker: UIViewControllerRepresentable {
    var selected: (PhotoImageLoader?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(selected: selected) }
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images; configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let controller = PHPickerViewController(configuration: configuration)
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}
    @MainActor final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let selected: (PhotoImageLoader?) -> Void
        init(selected: @escaping (PhotoImageLoader?) -> Void) { self.selected = selected }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else { selected(nil); return }
            selected(PhotoImageLoader(provider: provider))
        }
    }
}

/// NSItemProvider/Progress are guarded across cancellation and callback queues.
final class PhotoImageLoader: @unchecked Sendable {
    private let provider: NSItemProvider
    private let lock = NSLock()
    private var progress: Progress?
    private var cancelled = false
    init(provider: NSItemProvider) { self.provider = provider }
    func cancel() {
        lock.lock(); cancelled = true; let progress = progress; lock.unlock()
        progress?.cancel()
    }
    func load() async throws -> Data {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let supported = provider.registeredTypeIdentifiers.first { identifier in
                guard let type = UTType(identifier), let mime = type.preferredMIMEType else { return false }
                return ["image/png", "image/jpeg", "image/heic", "image/heif"].contains(mime)
            }
            guard let supported else { throw ImportFailure.unsupportedImage }
            return try await withCheckedThrowingContinuation { continuation in
                let progress = provider.loadDataRepresentation(forTypeIdentifier: supported) { data, error in
                    if error != nil || data == nil { continuation.resume(throwing: ImportFailure.unavailableFile) }
                    else { continuation.resume(returning: data!) }
                }
                lock.lock(); self.progress = progress; let stopped = cancelled; lock.unlock()
                if stopped { progress.cancel() }
            }
        } onCancel: { self.cancel() }
    }
}
