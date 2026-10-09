# Guided receipt camera

Choose **Import receipt → Take a photo**. Sliplet opens a full-screen rear-camera preview with rounded corner guides, frosted guidance and soft shading behind the controls. A short reminder asks you to keep all four edges visible and avoid glare. Landscape places the guide beside the controls. Glass controls match the rest of the app. Cancel and confirmation actions use the shared 44-point baseline; the capture shutter uses a familiar 72-point camera target. Controls and guidance grow with Dynamic Type, with vertically arranged photo-confirmation actions when needed. Reduced Motion removes the capture-state fade.

Tap the shutter, then check the photo. **Retake** drops that capture and resumes the camera. **Use photo** closes capture before starting the existing local Vision/parser review. Nothing is saved until you explicitly save a draft or finish a reviewed receipt. The original encoded image, including orientation, is retained; the guide does not crop it. The confirmation preview alone is downsampled. Capture does not write to Photos or request microphone access. Flash is off; supported continuous focus/exposure/white balance modes are enabled.

Camera permission is requested when you enter capture. Denied access offers **Open Settings** and an existing-image alternative; restricted access offers the alternative. An unavailable camera—including Simulator—returns you to Photos/Files choices. Capture/start failures offer retry. Session setup, start/stop and output work run on a serial queue. The camera stops during inactivity, confirmation, dismissal and backgrounding. Backgrounding discards unaccepted captures, following the app's existing unsaved-work policy. Photos and Files imports remain available.

Rotation follows Apple's [camera rotation coordinator](https://developer.apple.com/documentation/avfoundation/avcapturedevice/rotationcoordinator), for both the live preview and encoded capture orientation. Session startup follows the [AVCaptureSession API](https://developer.apple.com/documentation/avfoundation/avcapturesession/startrunning()).

## Try it on your iPhone

1. Open `Sliplet.xcodeproj`, keep your Personal Team selected, choose your connected iPhone as the run destination, and press **Command-R**.
2. Tap **Import receipt → Take a photo** and allow Camera access.
3. Put the receipt on a plain surface in even light. Include its top and bottom inside the guide; move farther away for long receipts. Tap the shutter.
4. Check sharpness and edges. Try **Retake**, then **Use photo**. In review, open **Original** and check items, date and printed totals. Save a draft if anything still needs correction.
5. Try portrait and landscape, a short and a long receipt, and cancellation. Lock/background the app with an unaccepted photo, then return; capture should be gone. Check both home/detail paper motion on the physical device too.

If you denied Camera, use **Open Settings**, enable Camera for Sliplet, and reopen **Take a photo** after returning to the app. Apple Intelligence is not used by this workflow.

## Verification scope

Simulator has no physical camera. Debug tests inject clearly fictional image bytes and camera states only when the isolated synthetic store is explicitly selected. They test the actual confirmation-to-Vision/parser-to-storage path, cancellation, background clearing, permission alternatives, retries, large text and landscape. Release excludes those injection branches. Actual permission prompts, live orientation, autofocus/exposure and receipt sharpness require the physical test above; an unsigned iPhone SDK build establishes compilation, not hardware capture. Evidence: [guided camera validation](evidence/t08-camera/README.md).
