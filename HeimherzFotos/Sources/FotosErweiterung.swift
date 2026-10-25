import ExtensionFoundation
import Photos

/// Stub (T4): tut nichts. Das Modul `ios-fotos` (T6) ersetzt diese Datei.
/// iOS 26.1 kennt nur dieses synchrone Protokoll; `PHBackgroundResourceUploadJobExtension` (async) gibt es erst mit iOS 27.
/// Quelle: developer.apple.com/documentation/photos/phbackgroundresourceuploadextension
@main
final class FotosErweiterung: PHBackgroundResourceUploadExtension {
    required init() {}

    func process() -> PHBackgroundResourceUploadProcessingResult { .completed }

    func notifyTermination() {}
}
