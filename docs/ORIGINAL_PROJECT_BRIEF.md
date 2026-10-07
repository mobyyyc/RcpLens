# Project Master Prompt — Receipt OS / Personal Purchase Graph

You are acting as the lead product engineer, mobile architect, security engineer, and technical project planner for this project.

Your job is NOT to blindly implement the architecture described below.

Your job is to:

1. Understand the product vision.
2. Critically evaluate the proposed architecture.
3. Research/verify the current state of relevant frameworks and APIs when necessary.
4. Replace any proposed technical choice if you have a clearly better option.
5. Record important architectural decisions and reasoning.
6. Produce a concrete MVP development plan.
7. Break the MVP milestones into small implementation tasks.
8. Create a progress-tracking system that can be continuously updated as development proceeds.
9. Prioritize building and validating the MVP rather than prematurely implementing the long-term roadmap.

Do not over-engineer the first version.

However, avoid architectural decisions that would make future features such as cloud sync, warranty tracking, tax/rebate analysis, purchase history, household sharing, or insurance evidence unnecessarily difficult.

---

# 1. PRODUCT VISION

Working concept:

**A searchable memory of everything you have ever bought.**

The product begins with receipts.

A receipt currently contains valuable structured information that normally becomes useless after purchase:

- merchant
- date
- individual products
- quantity
- price
- discounts
- tax
- total
- proof of purchase
- purchase ownership
- shared expenses

Instead of treating receipts as temporary images, this product turns them into a long-lived personal purchase database.

A user's bank knows:

> Costco — $187.43

This product should eventually know:

> Costco  
> October 7, 2026  
> Striploin — $42.81  
> Milk — $6.49  
> Laundry detergent — $21.99  
> USB-C cable — $14.99  
> etc.

Long term, this structured purchase history could power:

- expense analysis
- shared bill splitting
- price history
- product search
- warranty tracking
- return deadlines
- price adjustment detection
- insurance proof of ownership
- product recalls
- tax-document preparation
- potential government rebate detection
- purchase evidence packages
- resale history
- household inventory
- bank transaction matching
- email receipt ingestion
- purchase-related AI queries

However:

**Most of those features are NOT part of the MVP.**

The MVP exists to validate whether users are willing to continuously scan receipts if the immediate experience is useful enough.

---

# 2. PRIMARY MVP PRODUCT HYPOTHESIS

The MVP should test this hypothesis:

> Users will repeatedly scan receipts if scanning is fast, extraction is accurate enough, correcting mistakes is easy, and the resulting data gives immediate value through item-level bill splitting and searchable purchase history.

The most important metric is therefore NOT number of downloads.

The important question is:

> Do users voluntarily scan another receipt after the novelty wears off?

---

# 3. MVP PRODUCT LOOP

The primary product loop should be approximately:

Receipt
↓
Take photo / import image
↓
On-device OCR
↓
Receipt parsing
↓
Structured receipt
↓
Fast review / correction
↓
Save
↓
Optional bill split
↓
Searchable forever

The entire interaction should feel substantially easier than manually entering receipt information.

---

# 4. PRODUCT POSITIONING

Do NOT position the first version as:

- a budgeting app
- an accounting app
- a tax app
- an expense tracker
- an AI finance advisor

The product is closer to:

**Personal Purchase Memory**

or

**Personal Purchase Graph**

The receipt is simply the initial data-ingestion mechanism.

A potential positioning sentence:

> Scan every receipt. Never lose the value in it.

Another:

> A searchable memory of everything you've ever bought.

---

# 5. RECOMMENDED PLATFORM STRATEGY

My current default recommendation is:

## Mobile first

Primary application:

- React Native
- Expo
- TypeScript

Initial beta:

- iOS first
- TestFlight
- Canadian users / Canadian receipts initially

Then:

- Android

Possible later surfaces:

- lightweight web viewer
- web dashboard
- share pages
- desktop utilities

Do NOT make the Web app the primary MVP.

The core workflow depends heavily on:

- camera access
- photo import
- fast scanning
- local secure storage
- offline capability
- biometric/device security
- document OCR

which strongly favors mobile.

---

# 6. WHY IOS-FIRST, NOT IOS-ONLY

iOS-first is a product-validation decision, not a permanent product limitation.

The architecture should avoid unnecessarily coupling business logic to iOS.

Ideally:

UI / Domain Logic
↓
Receipt Recognition Interface
↓
Platform implementation

For example:

ReceiptRecognitionProvider

could have implementations such as:

AppleVisionReceiptRecognizer

MLKitReceiptRecognizer

CloudFallbackRecognizer

MockReceiptRecognizer

Do not necessarily use these exact names.

The important idea is that receipt recognition should be abstracted from the rest of the application.

---

# 7. OCR TECHNICAL SPIKE BEFORE COMMITTING

Before locking the OCR architecture, create a small benchmark.

Compare reasonable current options such as:

- Apple Vision document/text recognition
- Google ML Kit text recognition
- another high-quality on-device option if one exists

Evaluate them using the SAME receipt dataset.

Important dimensions:

- merchant recognition
- date recognition
- item line recognition
- prices
- tax
- subtotal
- discounts
- total
- receipt layout
- speed
- offline behavior
- implementation complexity
- iOS/Android portability

If Apple Vision provides meaningfully better receipt structure extraction but requires a small native bridge, that may be worth doing.

If ML Kit performs nearly as well and drastically simplifies cross-platform development, it may be better for the MVP.

Make this an evidence-based decision.

Document the result in an Architecture Decision Record.

Do not select an OCR system solely because this prompt recommends it.

---

# 8. AI / LLM POLICY

An LLM may eventually help normalize messy receipt text.

However, the MVP should NOT require sending every receipt image to a cloud AI service.

Preferred model:

Image
↓
on-device OCR
↓
raw OCR text/layout
↓
local deterministic parsing
↓
optional fallback

If a cloud LLM fallback becomes useful:

- place it behind an explicit architecture boundary
- preferably send OCR text rather than the original image
- redact irrelevant identifiers first
- never send payment-card numbers
- never send loyalty identifiers unless clearly required
- use strict structured output
- validate output before accepting it
- never trust LLM arithmetic
- never let an LLM calculate final money allocations
- log no receipt contents
- make provider replacement easy
- verify provider privacy/data-retention terms before production use

The MVP should remain useful even if the cloud AI fallback is disabled.

---

# 9. RECEIPT PROCESSING PIPELINE

Design the processing pipeline approximately as:

## Step A — Capture

User:

- takes a photo
- OR selects an existing receipt image

Potential later input types:

- PDF
- email
- screenshot
- digital receipt
- retailer account import

Do not implement those yet unless they are nearly free.

## Step B — Image preprocessing

Potential processing:

- orientation correction
- perspective correction
- crop
- contrast normalization
- glare / blur detection
- receipt boundary detection
- image compression

Avoid destructive preprocessing if it hurts OCR.

Preserve an original normalized receipt image.

## Step C — OCR

Extract:

- raw text
- text blocks
- lines
- bounding boxes
- confidence if available

## Step D — Receipt interpretation

Extract:

Merchant

Purchase date/time

Currency

Items

For each item where possible:

- raw description
- normalized human-readable description
- SKU/item number if available
- quantity
- unit price
- line total
- discount
- tax marker
- confidence

Receipt-level fields:

- subtotal
- discounts
- tax lines
- deposit
- tip
- other adjustments
- final total

## Step E — Reconciliation

The application should mathematically validate the receipt.

For example:

sum(items)
- discounts
+ taxes
+ adjustments
≈ total

Money calculations must use integer minor units such as cents.

Never use floating-point arithmetic for financial calculations.

If the numbers do not reconcile:

mark the receipt as requiring review.

Do not silently invent adjustments.

## Step F — Confidence

Every extracted field should conceptually have:

- extraction source
- confidence
- user-verified status

Low-confidence fields should be visually emphasized during review.

## Step G — Human review

The user should be able to correct the entire receipt quickly.

The review UX is extremely important.

The goal is NOT:

"AI must be perfect."

The goal is:

"AI is good enough that fixing it is much faster than manual entry."

## Step H — Save

Save structured data and original receipt evidence.

---

# 10. MVP USER EXPERIENCE

Avoid building a finance-dashboard-heavy UI.

The core surfaces should initially be something like:

## Home

Primary CTA:

**Scan receipt**

Secondary content:

Recent receipts

Search

Possibly:

recent split

Do not overload the home screen with charts.

---

## Capture

Camera view with simple guidance.

Potential hints:

- receipt edges
- lighting quality
- blur warning
- glare warning

Capture should feel extremely fast.

---

## Processing

Avoid long fake animations.

Show a lightweight state such as:

Reading receipt…

Parsing items…

Then immediately move into review.

---

## Receipt Review

This may become the most important screen in the app.

Show:

Merchant

Date

Items

Prices

Subtotal

Tax

Total

Original receipt image accessible nearby.

Low-confidence fields should be obvious.

Editing should be extremely fast.

Possible interactions:

tap text → edit

tap amount → edit

swipe/delete invalid line

add missing line

merge accidental split lines

Users should always understand what the system extracted.

---

## Receipt Detail

Show:

Merchant

Date

Items

Receipt total

Original receipt image

Split information if applicable

Searchable text

Eventually this becomes the long-term "purchase record."

---

# 11. BILL SPLITTING — MVP KILLER FEATURE

Bill splitting should be part of the first real MVP.

Do NOT require every participant to create an account.

The receipt owner should be able to create local people such as:

Richard

Alex

Kevin

Then assign each item.

Example:

Milk → Richard + Alex

Detergent → Alex

Steak → Richard

Paper towels → Everyone

Support at least:

- one person owns item
- multiple people share item equally

Consider supporting:

- quantity splitting

if it is straightforward.

Example:

4 drinks

Richard: 1

Alex: 2

Kevin: 1

Do NOT make complicated arbitrary percentage splitting a priority unless it is easy.

---

# 12. TAX / DISCOUNT SPLITTING

Receipt splitting must produce totals that exactly reconcile with the receipt.

Design a deterministic cent-level allocation algorithm.

Handle:

- discounts
- taxes
- shared items
- rounding

Where item-specific tax information is unavailable, define a transparent fallback rule.

Potential approach:

allocate tax proportionally across applicable item subtotals.

If receipt tax markers identify taxable items, use them.

Use deterministic rounding, such as a largest-remainder-style method, so:

sum(participant totals) == receipt total

ALWAYS.

Write strong tests for this.

Do not use AI for this calculation.

---

# 13. SPLIT OUTPUT

Initial sharing does NOT require live collaborative accounts.

V1 could simply generate:

Richard — $82.43

Alex — $54.18

Kevin — $21.82

With a human-readable item summary.

Then provide:

Share

Copy

Generate image/card

Possibly generate a temporary link later.

Avoid building complex multiplayer collaboration before validating demand.

---

# 14. SEARCH — SECOND MVP KILLER FEATURE

Users should be able to search their saved receipts.

Examples:

airpods

ribeye

detergent

costco

milk

USB cable

Search should find:

merchant

raw item description

normalized item description

possibly SKU

Start with local full-text search.

SQLite FTS is likely sufficient.

Do NOT build embeddings / semantic search yet unless there is a compelling reason.

Future natural-language search can be added later.

---

# 15. DATA MODEL PRINCIPLES

The data model needs to support both the current MVP and future Purchase Graph features.

Important principles:

## Money

Store money as integer minor units.

Example:

$12.34 CAD

amount_minor = 1234

currency = CAD

Never store financial values as binary floats.

---

## IDs

Use globally unique IDs suitable for future sync.

Consider UUIDv7, ULID, or another sensible modern ID.

---

## Soft deletion / sync readiness

Consider fields such as:

created_at

updated_at

deleted_at

version / revision

device_id

Do not implement a CRDT unless actually needed.

But avoid designing tables that assume only one device will ever exist.

---

# 16. PROPOSED CORE ENTITIES

Treat this as a starting proposal, not a mandatory schema.

## Receipt

Possible fields:

id

merchant_raw

merchant_normalized

purchase_datetime

timezone if known

currency

subtotal_minor

tax_minor

discount_minor

adjustment_minor

total_minor

status

parser_version

review_status

created_at

updated_at

deleted_at

device_id

Do not blindly duplicate fields if a cleaner normalized model exists.

---

## ReceiptAsset

Represents original receipt evidence.

Potential fields:

id

receipt_id

local_uri

mime_type

width

height

sha256

encryption_version

cloud_object_path nullable

created_at

---

## ReceiptLine

Possible fields:

id

receipt_id

sort_order

raw_text

normalized_name

sku nullable

quantity nullable

unit nullable

unit_price_minor nullable

line_total_minor

discount_minor nullable

tax_code nullable

category nullable

confidence nullable

user_verified

source_metadata

---

## ReceiptTaxLine

Examples:

GST

HST

PST

Other tax

Possible:

label

rate

amount_minor

---

## ReceiptAdjustment

Potential types:

coupon

discount

deposit

tip

fee

rounding

other

---

## Participant

For MVP this may be local.

Fields:

id

display_name

created_at

Potential future relation to registered users should remain possible.

---

## Split

receipt_id

created_at

status

---

## SplitAllocation

Potential relation:

split

receipt_line

participant

weight / quantity

allocated_subtotal_minor

allocated_tax_minor

allocated_total_minor

The exact design is yours to determine.

The key invariant is:

all allocations must exactly reconcile to the receipt total.

---

# 17. DATA PROVENANCE

A future tax/insurance/warranty system needs evidence.

Therefore avoid destroying extraction provenance.

Consider preserving:

- original receipt image
- raw OCR
- parser output
- parser version
- extraction confidence
- corrections made by user
- original raw item description

Do NOT overwrite raw extracted information when the user edits a normalized label.

Example:

raw:

KS STPLN AAA

normalized:

Kirkland Signature AAA Striploin Beef

Both may be valuable later.

---

# 18. LOCAL-FIRST STORAGE

Default architecture:

## Structured data

Encrypted SQLite.

Prefer SQLCipher or an equivalent mature solution.

Database encryption key:

stored using platform secure key storage:

iOS Keychain

Android Keystore

Do not hardcode keys.

Do not derive keys from something predictable like user ID.

---

## Receipt images

Use app-private storage.

Avoid leaving receipt copies in temporary cache unnecessarily.

After capture:

1. import into controlled application storage
2. normalize as needed
3. remove temporary capture file when safe

Avoid storing sensitive metadata that is unnecessary.

For example, consider removing EXIF location information unless a real product need exists.

---

# 19. APPLICATION-LEVEL FILE ENCRYPTION

Evaluate whether original receipt images should also be encrypted at the application layer.

If implemented:

use standard authenticated encryption such as AES-GCM through a mature, audited implementation.

Do NOT implement custom cryptography.

However:

do not add a dangerous homegrown crypto layer simply to claim "everything is encrypted."

Platform-private storage + OS protection may be preferable to badly implemented custom encryption.

Document the decision.

---

# 20. BIOMETRIC / APP LOCK

Consider optional:

Face ID

Touch ID

Android biometrics

for unlocking the application.

This should be a defense-in-depth privacy feature.

It should not replace real authorization controls if cloud sync is later introduced.

---

# 21. CLOUD STRATEGY

Cloud should not be mandatory for the earliest MVP unless product testing requires it.

A user should ideally be able to:

scan

review

split

save

search

offline.

This reduces:

- infrastructure
- privacy exposure
- cost
- authentication friction
- development complexity

---

# 22. FUTURE CLOUD ARCHITECTURE

When cross-device sync becomes valuable, a practical candidate is:

Supabase

Postgres

Auth

Private object storage

Server/Edge functions where necessary

But treat this as a recommendation, not an absolute requirement.

If a better architecture exists, explain why.

Requirements if using Supabase:

- RLS on every exposed user-data table
- private Storage buckets
- strict Storage policies
- never ship service-role credentials in clients
- privileged operations only server-side
- short-lived signed URLs where appropriate
- no publicly enumerable receipt URLs
- explicit account deletion
- explicit receipt deletion
- rate limiting where needed
- backup strategy for BOTH database and receipt objects

Do not assume database backup automatically protects object storage.

---

# 23. FUTURE END-TO-END ENCRYPTION

Do NOT advertise the product as end-to-end encrypted unless it truly is.

A future E2EE architecture could be valuable because purchase history may be sensitive.

However, E2EE creates real complexity:

- search
- sharing
- multiple devices
- key recovery
- account recovery
- server processing
- AI analysis

Therefore:

do not casually implement E2EE in the MVP.

Instead:

build clean data boundaries now so E2EE can be investigated later.

---

# 24. LOGGING POLICY

Receipt contents must NEVER accidentally appear in logs.

Avoid logging:

- OCR text
- item descriptions
- receipt images
- user-entered purchase notes
- payment information
- loyalty identifiers
- full storage paths containing personal information

Production logs should use:

receipt IDs

request IDs

error codes

timings

parser versions

not receipt contents.

---

# 25. ANALYTICS POLICY

If analytics are used during beta, collect only what is necessary to validate the product.

Useful events may include:

receipt_scan_started

receipt_scan_completed

receipt_review_completed

receipt_saved

split_started

split_completed

search_used

receipt_deleted

But analytics should NOT include:

receipt image

OCR text

product names

merchant unless justified

exact price

search query text

personal names

participant names

Prefer boolean/count/timing metadata.

For example:

receipt_review_completed

duration_ms

number_of_lines

number_of_corrected_fields

ocr_provider

parser_version

Do not send the actual corrections.

If third-party analytics are used, document them as data processors.

---

# 26. CRASH REPORTING

If crash reporting is added:

scrub all sensitive breadcrumbs.

Ensure no receipt text or images can enter:

exception metadata

breadcrumbs

network captures

screenshots

logs

Before enabling automatic screenshot/session replay features from any analytics provider, explicitly evaluate the privacy implications.

Default should be OFF for session recording.

---

# 27. PRIVACY PRINCIPLES

Treat privacy as a product property.

Apply:

data minimization

purpose limitation

explicit retention policy

clear user deletion

clear export

least privilege

privacy-preserving defaults

Do not collect data "because it may be useful someday."

Receipt data can reveal:

location

health purchases

alcohol

food habits

financial behavior

household information

religious purchases

personal relationships

and much more.

Treat purchase history as sensitive personal information.

---

# 28. DATA EXPORT

Even the MVP should be designed so users can eventually export their data.

Potential future export:

JSON

CSV

receipt images

Prefer a structure that does not trap the user.

This fits the long-term philosophy of user-owned purchase history.

---

# 29. DATA DELETION

Users must be able to delete:

an individual receipt

all receipts

eventually their entire account

Deletion behavior should be tested.

Avoid orphaned receipt images.

---

# 30. MVP FEATURE SET

The first externally testable MVP should include approximately:

### Required

Receipt camera/import

On-device OCR

Receipt parsing

Merchant/date extraction

Line-item extraction

Subtotal/tax/total extraction

Confidence / error review

Manual correction

Encrypted local storage

Original receipt preservation

Receipt history

Receipt detail

Item-level bill splitting

Multiple participants

Shared item splitting

Correct tax/discount allocation

Shareable split summary

Full-text purchase search

Receipt deletion

Basic privacy/settings page

Basic export or at minimum architecture ready for export

Privacy-safe telemetry if needed for testing

### Strongly consider

Biometric app lock

Blur/glare detection

Basic generic merchant parser

Several retailer-specific parser improvements

### Explicitly NOT MVP

Bank integrations

Plaid-style account linking

Automatic tax filing

Government rebate eligibility decisions

Warranty claims

Return monitoring

Price-drop monitoring

Product recalls

Insurance claim packages

Household multi-user accounts

Receipt email ingestion

Gmail integration

Amazon account scraping

Retailer account scraping

Semantic embeddings

RAG

AI chat

Complex budgeting charts

Investment features

Credit score

Financial advice

Live collaborative split editing

---

# 31. INITIAL RETAILER STRATEGY

Do NOT try to support every receipt format perfectly.

Build:

generic parser

+

retailer-specific adapters where evidence shows they are useful.

For Canadian beta testing, likely candidates include some subset of:

Costco

Walmart

Loblaws / No Frills / Real Canadian Superstore

Shoppers Drug Mart

T&T

FreshCo

Metro

restaurants

Do not hardcode this list blindly.

Use actual testing data to prioritize.

Architecture could conceptually resemble:

GenericReceiptParser

CostcoReceiptParser

WalmartReceiptParser

etc.

But avoid duplicated logic.

Use shared parsing primitives.

---

# 32. NORMALIZATION

Do NOT attempt perfect global SKU/product normalization in MVP.

Initially preserve:

raw description

and optionally generate:

normalized display name

Example:

raw:

KS STPLN

normalized:

Kirkland Signature Striploin

The MVP does NOT need to know the universal canonical product ID.

Long-term product identity resolution may become its own major system.

Avoid building it prematurely.

---

# 33. TEST DATA

Create a privacy-safe receipt evaluation corpus.

Prefer:

real receipts where consent exists

plus

synthetic receipts where useful

Anonymize where possible.

Remove:

credit card fragments if unnecessary

loyalty identifiers

membership numbers

personal names

addresses when unnecessary

Do not commit sensitive real receipts into a public repository.

If private test fixtures are needed:

store them outside source control or in a protected test-data location.

---

# 34. GOLDEN RECEIPT TEST SET

Create a golden dataset.

For every receipt:

image

expected merchant

expected date

expected line items

expected prices

expected tax

expected total

This allows regression testing across OCR/parser changes.

Do not judge parser quality by looking at a few screenshots manually.

Build measurable evaluation.

---

# 35. OCR/PARSER QUALITY METRICS

Track at least:

Merchant exact accuracy

Date exact accuracy

Receipt total exact accuracy

Subtotal exact accuracy

Tax exact accuracy

Number of line items detected

Line-item amount accuracy

Description usefulness

Receipt reconciliation success rate

Processing latency

User correction count

User correction time

Potential starting targets — adjust based on reality:

merchant/date/total exact accuracy:
~95% on supported retailer test set

line item totals:
~90%+ exact or near exact

receipts requiring <=2 corrections:
target a strong majority

median scan → review time:
single-digit seconds if technically realistic

median review/correction time:
ideally well under 30 seconds

These are targets, not dogma.

Measure first.

---

# 36. SPLIT ENGINE TESTING

Financial correctness should be deterministic.

Create comprehensive unit tests covering:

simple individual items

equal shared item

multiple shared items

discounts

tax

non-taxable items

taxable items

coupon

tip

deposit

odd-cent division

three-person division

quantity split

receipt rounding

negative adjustments

Ensure invariant:

sum(all participant totals)
==
receipt total

to the cent.

---

# 37. LOCAL DATABASE TESTS

Test:

create receipt

edit receipt

delete receipt

search receipt

migration

corrupt/incomplete write recovery where practical

database encryption enabled

key missing

app restart

app upgrade

schema migration

Do not lose existing receipts during application upgrades.

---

# 38. SECURITY TESTING

Use a mobile-security checklist influenced by OWASP MASVS.

At minimum review:

secure storage

key storage

authorization

network traffic

logs

temporary files

screenshots/app switcher previews

clipboard

backups

deep links

share links

debug builds

production build configuration

API keys

third-party SDKs

dependency vulnerabilities

jailbroken/rooted device behavior does not necessarily need blocking in MVP, but understand the risk.

---

# 39. RECEIPT SECURITY TEST

Explicitly test:

Capture receipt

Process receipt

Close app

Inspect application cache

Inspect logs

Inspect analytics

Inspect crash breadcrumbs

Inspect local filesystem if possible

Verify the receipt content has not leaked into unintended locations.

---

# 40. PRODUCT TESTING STAGES

## Internal dogfood

Start with the developer.

Scan approximately:

30–50 real receipts

across multiple merchants.

The developer should actually use the split feature.

Track every friction point.

---

## Closed alpha

Approximately:

5–10 trusted users.

Ask them to use the product naturally for about one week.

Important:

Do NOT constantly remind them to scan receipts.

We want to see whether they remember voluntarily.

Observe:

which receipts they scan

which receipts they ignore

why

how much correction is required

whether they use split

whether they search old purchases

what makes them stop scanning

---

## Small beta

Approximately:

20–50 users.

Run for roughly:

2–4 weeks.

Focus on retention and repeated behavior.

The MVP succeeds if users develop a habit.

---

# 41. MVP PRODUCT METRICS

Primary metric:

**repeat receipt capture**

Examples worth tracking:

Receipts scanned per user

Users who scan >=3 receipts

Users who scan again in week 2

Median receipts per active user

Scan completion rate

Review abandonment rate

Correction count

Correction time

Split usage among relevant receipts

Search usage

Receipt reopen rate

---

# 42. USER INTERVIEW QUESTIONS

During alpha/beta ask questions such as:

What made you decide to scan this receipt?

Which receipts did you choose not to scan?

Why?

Was fixing the parsed receipt annoying?

What was the most useful feature?

Did splitting save you time?

Have you searched for an old purchase?

Would you keep scanning if split disappeared?

Would you keep scanning if search disappeared?

What would make you scan every receipt?

Do you trust this app with your purchase history?

What privacy concern do you have?

Would you prefer local-only storage?

Would you use cloud backup?

Would you pay for this eventually?

Do not lead users toward future tax/warranty features unless they bring up those problems naturally.

---

# 43. MVP SUCCESS SIGNAL

The strongest success signal is something like:

> Users continue scanning receipts after the initial testing period without being reminded.

A strong secondary signal:

> Users search for something they bought previously and successfully find it.

A strong sharing signal:

> Users choose the receipt split workflow instead of manually using Calculator / Notes / Splitwise-style entry.

---

# 44. REPOSITORY STRUCTURE

Choose a sensible monorepo or single-app structure.

Do not add a monorepo merely because it sounds scalable.

Possible logical modules:

app/mobile

packages/domain

packages/receipt-parser

packages/split-engine

packages/data

packages/security

packages/test-fixtures

But if a simpler structure is better at MVP scale, use it.

The important separation is conceptual:

UI

domain

receipt recognition

receipt parsing

financial calculation

persistence

security

future sync

---

# 45. DOMAIN LOGIC

Keep important business logic outside UI components.

Examples:

receipt reconciliation

money calculations

tax allocation

split calculations

parsing

search indexing

should be unit-testable independently.

---

# 46. TYPE SAFETY

Use strict TypeScript.

Define explicit domain schemas.

Consider schema validation such as Zod or an appropriate alternative at boundaries.

Validate:

OCR parser output

database input

cloud response if cloud exists

import/export data

Never trust an LLM response merely because TypeScript says it has a type.

---

# 47. DATABASE MIGRATIONS

Use real migrations from the beginning.

Do not mutate SQLite schema ad hoc during development.

Each migration should:

have a version

be testable

preserve existing data

Support upgrading an existing beta install.

---

# 48. ARCHITECTURAL DECISION RECORDS

Create ADRs for major decisions.

Examples:

ADR-001 Mobile framework

ADR-002 OCR provider

ADR-003 Local database

ADR-004 Receipt image storage

ADR-005 Encryption strategy

ADR-006 Cloud sync strategy

ADR-007 Analytics strategy

ADR-008 Receipt parser architecture

Each ADR should include:

Context

Options considered

Decision

Why

Tradeoffs

Revisit conditions

Do not create ADRs for trivial decisions.

---

# 49. REQUIRED PROJECT DOCUMENTATION

Please create or propose documentation similar to:

README.md

docs/PRODUCT.md

docs/ARCHITECTURE.md

docs/PRIVACY.md

docs/THREAT_MODEL.md

docs/DATA_MODEL.md

docs/OCR_EVALUATION.md

docs/TEST_PLAN.md

docs/adr/

PROGRESS.md

MVP_PLAN.md

Exact paths may change if you have a better organization.

---

# 50. PROGRESS SYSTEM

Create a lightweight persistent progress system.

PROGRESS.md should show:

Current milestone

Completed tasks

Current task

Blocked tasks

Important findings

Architecture decisions

Known issues

Next recommended task

Avoid turning PROGRESS.md into a massive historical log.

Move historical detail somewhere else if necessary.

---

# 51. TASK BREAKDOWN FORMAT

Break MVP milestones into small tasks.

Each task should contain roughly:

Task ID

Title

Goal

Why

Dependencies

Implementation scope

Acceptance criteria

Tests

Risk / notes if relevant

Status

Prefer tasks that correspond to one coherent change / PR.

Avoid tasks that are:

"Build receipt system"

Too large.

Avoid tasks that are:

"Rename variable"

Too small.

A good task should usually be independently verifiable.

---

# 52. DEVELOPMENT STAGES

Use the following as the initial milestone structure.

You may rename, combine, or reorder milestones if you find a better plan.

---

# MILESTONE 0 — PRODUCT + TECHNICAL VALIDATION

Goal:

Remove major unknowns before building the application deeply.

Work may include:

Create product specification

Create threat model

Create initial data model

Set up golden receipt dataset

Build OCR spike

Benchmark Apple Vision / ML Kit / alternatives

Test receipt parsing approaches

Choose mobile framework

Choose local storage

Choose encryption approach

Design split algorithm

Create architecture ADRs

Define MVP metrics

Exit condition:

We understand how the main technical pipeline will work and have evidence supporting major architectural choices.

---

# MILESTONE 1 — SECURE MOBILE FOUNDATION

Goal:

A production-quality skeleton capable of safely storing receipt data.

Work may include:

Create app

Navigation

Design tokens/components

Local database

SQLCipher/encryption if selected

Secure key storage

Database migrations

Receipt domain models

Repository/data layer

Privacy-safe logging

Basic settings

Tests

Exit condition:

The app can securely create/read/update/delete a fake structured receipt locally.

---

# MILESTONE 2 — RECEIPT CAPTURE + OCR

Goal:

Take a real receipt photo and convert it into OCR output.

Work may include:

Camera

Photo import

Permission UX

Image preprocessing

OCR abstraction

Selected OCR provider

OCR test fixtures

Processing states

Temporary-file cleanup

Performance measurement

Exit condition:

User can photograph common receipts and receive OCR text/layout locally.

---

# MILESTONE 3 — RECEIPT UNDERSTANDING + REVIEW

Goal:

Turn OCR into reliable structured receipts.

Work may include:

Generic parser

Merchant detection

Date detection

Money parsing

Line item extraction

Tax

Subtotal

Discounts

Total

Reconciliation

Confidence

Review screen

Correction UI

Parser regression tests

Retailer adapters where justified

Exit condition:

User can scan, review, correct, and save real receipts with reasonable effort.

This is one of the most important milestones.

---

# MILESTONE 4 — ITEM-LEVEL SPLITTING

Goal:

Create immediate utility from scanned receipts.

Work may include:

Participants

Item assignment

Shared items

Quantity split if appropriate

Tax allocation

Discount allocation

Rounding

Split summary

Share/copy

Financial correctness test suite

Exit condition:

Users can split a receipt and every participant amount reconciles exactly to the receipt total.

---

# MILESTONE 5 — PURCHASE MEMORY + SEARCH

Goal:

Make saved receipt history useful later.

Work may include:

Receipt history

Receipt detail

FTS search

Merchant search

Product search

Filters if clearly useful

Original image viewer

Deletion

Exit condition:

User can find a previously purchased item quickly.

---

# MILESTONE 6 — PRIVACY + RELIABILITY HARDENING

Goal:

Prepare for external testers.

Work may include:

Biometric lock if selected

Data deletion audit

Export

Cache cleanup audit

Logs audit

Crash reporting review

Telemetry review

Security checklist

App lifecycle edge cases

Database migration tests

Performance tests

Backup behavior documentation

Threat model update

Exit condition:

We are comfortable allowing trusted beta users to store real purchase data.

---

# MILESTONE 7 — CLOSED BETA

Goal:

Validate whether the product behavior is worth continuing.

Work may include:

TestFlight setup

Onboarding

Privacy explanation

Telemetry

Bug reporting

User interview process

OCR accuracy dashboard/test script

Beta feedback workflow

Product metrics review

Exit condition:

We have enough real usage to answer:

Do users voluntarily continue scanning receipts?

---

# 53. IMPORTANT DEVELOPMENT PRIORITY

Optimize for:

Scan speed

Extraction quality

Correction speed

Data integrity

Split usefulness

Search usefulness

Privacy trust

Do NOT optimize early for:

growth loops

subscriptions

landing page conversion

social media

advanced AI

beautiful financial dashboards

backend scale

---

# 54. UX QUALITY BAR

The product should not feel like enterprise expense software.

Target feeling:

Apple Wallet

Apple Notes

modern consumer scanner

not:

QuickBooks

SAP

corporate reimbursement portal

The interaction should be visually calm, obvious, and fast.

---

# 55. ERROR PHILOSOPHY

Never pretend uncertain data is certain.

Example:

If item text confidence is low:

show it.

If receipt total fails reconciliation:

show it.

If the date is unknown:

ask.

If OCR fails:

allow manual entry or retake.

The product should build trust through visible uncertainty.

---

# 56. OFFLINE-FIRST

Core MVP should work without internet where practical:

capture

OCR if provider supports it

review

save

split

search

This is important both for privacy and product reliability.

---

# 57. FUTURE ROADMAP — DO NOT TASK-BREAK YET

Do NOT create detailed implementation tasks for these areas yet.

They are intentionally flexible.

Only preserve architectural optionality.

Potential future stages:

## Purchase Intelligence

Price history

Repeated product detection

Merchant comparison

Category analysis

Cost trends

## Product Ownership

Warranty

Return deadlines

Serial numbers

Manuals

Receipts as proof of ownership

## Purchase Recovery

Price adjustment

Recall detection

Warranty claim preparation

Return reminders

## Evidence

Insurance claim packages

Proof of ownership

Receipt + payment matching

## Taxes / Rebates

Potentially relevant expense detection

Receipt grouping

Evidence packages

Government rebate discovery

Never automatically state tax eligibility without reliable rules and appropriate disclaimers.

## Data ingestion

Email receipts

PDF receipts

Retailer integrations

Bank transaction matching

## Household

Shared household

Collaborative receipts

Family inventory

## AI interface

Ask:

"When did I buy my headphones?"

"How much did I spend on beef?"

"Find the Costco detergent I bought last month."

"What purchases may still be under warranty?"

Only build this once structured data quality is strong.

---

# 58. DO NOT LOCK FUTURE PRODUCT DIRECTION

The long-term roadmap is deliberately exploratory.

Do NOT create hundreds of tasks for future stages.

Do NOT design database tables for every hypothetical feature.

Instead:

build sensible extension points.

The product direction after MVP should be determined by user behavior.

---

# 59. TECHNICAL FREEDOM

You have explicit permission to replace recommendations in this prompt.

Examples:

If React Native is clearly inferior for this product:

propose SwiftUI or another approach.

If Supabase is inappropriate:

replace it.

If SQLCipher is unnecessary or creates unacceptable platform complexity:

explain and propose a better secure-storage architecture.

If ML Kit is better than Apple Vision:

use it.

If Apple Vision is significantly superior:

use it.

If a particular parser architecture is bad:

replace it.

However:

Do not make arbitrary changes.

For significant deviations:

document:

What changed

Why

Evidence

Tradeoff

---

# 60. BEFORE IMPLEMENTING

First inspect the repository.

Determine:

current files

existing technology

existing conventions

whether anything has already been implemented

Do not overwrite good existing work.

Then produce:

## A. Architecture assessment

What you recommend

What you would change from this prompt

Why

## B. MVP specification

Precise MVP behavior

Non-goals

## C. Architecture diagram

Client

OCR

Parser

Storage

Future cloud boundary

## D. Data model

Tables/entities

Relationships

Important invariants

## E. Threat model

Assets

Threats

Mitigations

Remaining risks

## F. Milestone plan

Use or improve the milestone framework above.

## G. Detailed MVP task backlog

Break ONLY the MVP / near-term milestones into detailed small tasks.

Do not fully task-break the distant roadmap.

## H. Testing strategy

Unit

integration

parser regression

security

beta

## I. Progress tracking

Create/update:

PROGRESS.md

and the appropriate planning documentation.

---

# 61. TASK EXECUTION STYLE

Once planning is complete, execute work milestone by milestone.

For every task:

understand existing code first

implement the smallest coherent solution

write/update tests

run relevant tests

run lint/typecheck

verify acceptance criteria

update progress

avoid unrelated refactors

If an architectural assumption becomes invalid:

stop relying on it

document the finding

revise the plan

continue with the improved architecture.

---

# 62. QUALITY RULES

No silent financial rounding errors.

No unencrypted secrets.

No hardcoded production credentials.

No sensitive receipt contents in logs.

No service-level cloud secrets in mobile binaries.

No float money calculations.

No blind trust in OCR.

No blind trust in AI.

No irreversible destructive migrations.

No schema changes without migrations.

No shipping privacy-invasive analytics by accident.

No collecting user information without a real product purpose.

---

# 63. INITIAL DEFINITION OF DONE FOR MVP

A new user should be able to:

Install app

↓
Understand privacy model

↓
Take photo of receipt

↓
See extracted merchant/date/items/prices

↓
Fix mistakes quickly

↓
Save receipt

↓
Select people

↓
Assign items

↓
Receive mathematically correct split totals

↓
Share split summary

↓
Return days later

↓
Search for an item

↓
Find the original receipt

The experience should work with real-world receipts, not only synthetic examples.

---

# 64. FINAL MVP QUESTION

At the end of beta, the project should be able to answer:

**Does turning receipts into structured personal purchase memory create enough immediate value that people voluntarily keep scanning them?**

If yes:

continue expanding the Purchase Graph.

If no:

do not solve the problem by adding random features.

Study where the loop failed:

capture friction

OCR accuracy

correction burden

insufficient immediate value

privacy concerns

lack of habit

and redesign accordingly.

---

# YOUR FIRST ACTION

Do NOT immediately start writing large amounts of application code.

First:

1. inspect the repository;
2. evaluate this proposal;
3. identify the highest-risk assumptions;
4. perform necessary technical research/spikes;
5. produce the architecture + milestone + task plan;
6. create the project/progress documentation;
7. then begin Milestone 0 work.

Optimize for building the smallest high-quality product that can genuinely test the hypothesis.

Think independently.

The prompt defines the product vision and constraints.

It does not prescribe every implementation decision.