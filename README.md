# InkNote v1

Personal-use handwriting note app, built from scratch with SwiftUI,
PencilKit and PDFKit. See DEVELOPMENT_LOG.md for scope, the canonical
stroke model, validation results and the device checklist.

Repository: https://github.com/ashoru/InkNote

Build (on the iMac, unsigned, no IPA kept):

```sh
python3 tools/generate_project.py
xcodebuild -project InkNote.xcodeproj -scheme InkNote -sdk iphoneos \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

Releases are built by GitHub Actions (`.github/workflows/build-unsigned-ipa.yml`)
on `workflow_dispatch` with `publish_release` enabled. The Release
contains an unsigned IPA plus a `.sha256` file.

Unsigned IPA sideloading note: downloading the unsigned IPA alone
does not install it on a device. Sign it yourself, for example in
Xcode with your own Apple ID, or with a sideloading tool you trust,
before installing it on an iPhone or iPad.

Importer offline validation (on a Mac, Foundation-only, with your own
sample files, which are never committed to this repository):

```sh
swiftc Sources/CanonicalModel.swift Sources/BPlist.swift \
  Sources/NoteImporter.swift Sources/FormulaEvaluator.swift \
  Validation/main.swift -o /tmp/ImporterValidation
/tmp/ImporterValidation <sample1.note> <sample2.note> <sample3.note>
```
