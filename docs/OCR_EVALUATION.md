# Receipt extraction evaluation

Status: research plan only; no benchmark executed.

## Primary sources reviewed
- VisionKit document capture: https://developer.apple.com/documentation/visionkit/vndocumentcameraviewcontroller
- Structured document recognition: https://developer.apple.com/documentation/vision/recognizedocumentsrequest
- Foundation Models iOS 27 capabilities: https://developer.apple.com/ios/whats-new/
- Foundation Models updates: https://developer.apple.com/documentation/updates/foundationmodels
- Guided generation guarantees structure, not factual values: https://developer.apple.com/videos/play/wwdc2025/286/
- Model availability: https://developer.apple.com/documentation/FoundationModels/adding-intelligent-app-features-with-generative-models
- Simulator uses host model and needs compatible versions: https://developer.apple.com/forums/thread/787445

Verify availability in installed SDK and with a local smoke test. Do not infer actual receipt accuracy from general model documentation. Explicitly use on-device processing; do not enable Private Cloud Compute or another cloud fallback implicitly.

## Comparison
A. Vision + deterministic parser.
B. Same OCR + Foundation Models-assisted interpretation.
C. Supported image-assisted Foundation Models path on iOS 27.

Use identical private images and ground truth. Seed 3–5 receipts per retailer; expand toward ~30. Include long receipts, discounts, weighted goods, quantity cases and mixed-language text where present.

Measure merchant/date/total accuracy, line detection, exact amounts, omissions/inventions, reconciliation, latency, correction count/time. Record device and OS/model version. Synthetic data can validate plumbing but does not establish real-store accuracy. Money is calculated by deterministic code. Preserve evidence for every proposed field, and do not trust self-reported model confidence.
