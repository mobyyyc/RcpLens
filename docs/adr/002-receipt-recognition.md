# ADR 002 — Vision and deterministic parsing for the manual-review pilot

Date: 2026-10-07. Status: **accepted for the five-receipt pilot; broader accuracy remains provisional**.

## Context

T01 demonstrated Vision and a local model with fictional inputs. T03 evaluates extraction separately from app UI/storage on five consented private HEIC receipts and six fictional image fixtures. API availability, model agreement and matching totals cannot establish receipt accuracy. The corpus is below the desired 3–5 per retailer and approximately 30 overall.

## Decision

Use Vision plus deterministic parsing as the initial recognition route for T05, with mandatory source review/correction and deterministic reconciliation. Do not integrate B/C as automatic extraction paths in this pilot; retain them as isolated local evaluation variants. This is a measured pilot choice, not a claim of broad No Frills/Costco/T&T support or a complete production parser.

The user independently verified five original receipts (two Costco, two No Frills, one T&T). On 66 expected purchases, A recovered 57 exact amounts after validation, B 33 and C 26. A's correction proxy was 20 operations versus 61/60, and its exploratory median was 225 ms versus approximately 68/78 seconds. Before source rejection, raw B recovered 41/66 exact item amounts and raw C 26/66, so source binding alone does not explain the weaker model item result. Raw B improved total accuracy to 4/5, but neither model variant reduced the overall correction proxy. Matching item names is strict, and extra-line counts are proxies, not proven hallucinations.

**No approach reconciled any of the five receipts without correction.** A's total accuracy was 2/5. The demo must expose incomplete/mismatched data and require correction before treating a receipt as complete or finalizing a split. A is the best tested starting point, not an automatic receipt-completion guarantee. Actual human correction time remains unmeasured.

Retain both evaluated local AI variants: B interprets the same frozen OCR text; C uses an image attachment and Apple's OCRTool with `SystemLanguageModel.default`. Installed iOS 27 and Mac SDK declarations support this path; the actual benchmark executes on the Mac. Apple documents OCRTool as unavailable in Simulator. This does not establish physical iPhone behavior, so T05's simulator fallback remains Vision/text interpretation/manual review. No automatic cloud fallback is allowed.

## Guardrails and fallbacks

All money is parsed into integer minor units and reconciled deterministically. The model copies printed values and never computes tax, discount allocations or splits. Keep the original image, raw OCR/geometry, raw model response/transcript, normalized proposals and human labels separate. Claims need verbatim evidence; numeric substrings cannot ground an amount inside a larger amount, unit prices cannot masquerade as line extensions, and unrelated description/amount rows are rejected. Evidence grounding is a necessary check, not semantic correctness or calibrated confidence.

When AI is unavailable, refuses, fails structured generation, exceeds context or times out, retain Vision evidence and offer manual review. For long receipts, preserve all source rows and expose incomplete results; chunking is a future option that needs boundary/duplicate tests before integration. Never silently truncate or invent missing fields. Unsupported languages and unreadable images need correction or re-import. Don't finalize unexplained discrepancies.

## Evidence and remaining work

See [OCR evaluation](../OCR_EVALUATION.md), [harness instructions](../../evaluation/receipt-eval/README.md) and aggregate evidence under `docs/evidence/t03/`. Real field/item accuracy was scored against the five checked human labels, matched to unchanged original-image hashes. The local review page supplies optional unverified OCR drafts and requires explicit field/item/amount/adjustment checks; null reference values are unscored unknowns. Actual invented-content adjudication and timed correction burden remain unmeasured.

Revisit the decision after an expanded retailer corpus, parser/source-binding improvements, timed correction usability and device testing. Prefer the approach that reduces verified correction burden without weakening provenance, offline behavior or exact reconciliation. Real B produced equal successful output across five repeat pairs; real C had only one successful pair, with four pairs containing failures (six total timeouts). A long synthetic image also demonstrated that a successful structured response can omit essentially all expected items. API success and equal failures are insufficient evidence of extraction quality.

## Primary sources and SDK checks

- [Apple Foundation Models updates](https://developer.apple.com/documentation/updates/foundationmodels): iOS 27 image/tool analysis and model changes.
- [Apple OCRTool](https://developer.apple.com/documentation/vision/ocrtool): tool-assisted text recognition; Simulator restriction.
- [Apple LanguageModelSession](https://developer.apple.com/documentation/foundationmodels/languagemodelsession): local sessions/guided generation and context errors.
- [Apple context guidance](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window): schema/instructions/tools/responses contribute to the context window. The installed model's reported limit governs this run.
- Installed Xcode 27 Mac and iOS FoundationModels interfaces: `SystemLanguageModel.default`, `.capabilities`, `.vision`, `.toolCalling`, `.contextSize`, `.tokenCount`, `Prompt`, `Attachment(imageURL:)`, `LanguageModelSession(model:tools:instructions:)`, guided `respond` and greedy options. Vision's `_Vision_FoundationModels` cross-import overlay declares `OCRTool`; no external model provider is linked.
