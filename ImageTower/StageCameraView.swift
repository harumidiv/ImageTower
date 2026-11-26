import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct StageCameraView: UIViewControllerRepresentable {
    let onFinish: (Result<UIImage, SubjectProcessingError>?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier]
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (Result<UIImage, SubjectProcessingError>?) -> Void

        init(onFinish: @escaping (Result<UIImage, SubjectProcessingError>?) -> Void) {
            self.onFinish = onFinish
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage else {
                onFinish(.failure(.unreadableImage))
                return
            }
            onFinish(.success(image))
        }
    }
}
