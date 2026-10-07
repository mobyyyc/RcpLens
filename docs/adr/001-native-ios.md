# ADR-001: Native iOS app

Status: accepted by user direction, 2026-10-07.

## Context
The original brief proposed React Native/Expo for an iOS-first cross-platform app. The user subsequently chose iOS only and a wallet-style interface, with Apple-native OCR and on-device model evaluation.

## Options
React Native/Expo with native bridges; native Swift/SwiftUI.

## Decision
Use a single native Swift/SwiftUI iPhone app. Keep recognition, parsing, money, persistence and UI logically separated and independently testable.

## Reason
The cross-platform requirement was removed. Native code provides direct access to the Apple APIs being evaluated and control of the requested interactions.

## Tradeoffs
Domain implementation is in Swift and would need adaptation for another platform. Xcode and native iOS tooling are required. Native model API availability and extraction accuracy remain to be verified.

## Revisit
Only if the user later adds another platform or native integration evidence invalidates the approach. Do not build abstractions for hypothetical Android support now.
