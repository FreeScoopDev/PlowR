import SwiftUI
import UIKit

/// The camera, for every screen that takes a photo. Opening
/// `UIImagePickerController` on a device without a camera (some iPads, a Mac
/// running PlowR) throws, so it's done only here: a Camera button shows only
/// when `isAvailable`, and if one is reached anyway this says so instead of
/// crashing. The guard job in `guards.yml` fails a camera opened anywhere else.
struct CameraPicker: View {
    /// Whether this device has a camera.
    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    /// The photo, and the camera's metadata (its EXIF has the shutter time).
    let onCapture: (UIImage, [String: Any]?) -> Void

    var body: some View {
        if Self.isAvailable {
            Capture(onCapture: onCapture).ignoresSafeArea()
        } else {
            NoCamera()
        }
    }

    private struct NoCamera: View {
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                ContentUnavailableView("No Camera",
                                       systemImage: "camera",
                                       description: Text("This device doesn't have a camera."))
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                    }
            }
        }
    }

    private struct Capture: UIViewControllerRepresentable {
        let onCapture: (UIImage, [String: Any]?) -> Void

        func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

        func makeUIViewController(context: Context) -> UIImagePickerController {
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.delegate = context.coordinator
            return picker
        }

        func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

        final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
            let onCapture: (UIImage, [String: Any]?) -> Void
            init(onCapture: @escaping (UIImage, [String: Any]?) -> Void) { self.onCapture = onCapture }

            func imagePickerController(_ picker: UIImagePickerController,
                                       didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
                if let image = info[.originalImage] as? UIImage {
                    onCapture(image, info[.mediaMetadata] as? [String: Any])
                }
                picker.dismiss(animated: true)
            }

            func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
                picker.dismiss(animated: true)
            }
        }
    }
}
