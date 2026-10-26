# InkNote v1 — Development Log

> Personal-use handwriting note app, built from scratch.
> No other note app's code, assets, icons or trademarked name is used.
> Paper templates are drawn in code. PencilKit and PDFKit are Apple's
> public frameworks. The .note importer reads the user's own exported
> packages; the original .note file is never modified.
> This log is updated step by step. A step is only marked verified when
> a real command output supports it. "Build succeeded" is never presented
> as "device feel verified".

## 0. Scope decided (user approved)

- v1: canonical stroke model v1, notebook/folder management, PencilKit
  handwriting, PDF annotation, .note import validation.
- Interface-only in v1 (see FutureServices.swift, never faked as working):
  NAS sync, audio transcription, handwriting recognition, handwritten
  formula recognition. Typed formula evaluation (FormulaEvaluator.swift)
  is implemented in v1, because it needs no recognition step.
- Target: SwiftUI App, InkNote, bundle id com.ashoru.inknote,
  minimum iOS 18.0, iPhone + iPad universal.
- Build route (same as the project's standing practice): iMac via SSH,
  xcodebuild unsigned compile, no IPA kept, no GitHub push.

## 1. Canonical stroke model v1 — global impact, checked first

Model file: Sources/CanonicalModel.swift (Foundation-only).

Consumers, listed before any model change and checked after it:
- iPhone: NotebookListView (manifest + thumbnail only), NoteEditorView
  (canvas), PDFNoteView (PDF page overlay + export), ImportView
  (import -> canonical), thumbnail generation.
- iPad: same four views, plus the split-view detail pane in InkNoteApp.
- Shared, non-UI: DocumentStore (persistence), NoteImporter
  (.note -> canonical), PDF export (canonical -> PDF), future NAS sync,
  future handwriting recognition, future formula evaluation.

Model decisions and why:
- Note package on disk: manifest.json + pages.json are truth;
  thumb.png is regenerable cache; a PDF file, when present, is copied
  verbatim. Nothing else is truth.
- Per stroke: id, tool, RGBA colour, base width, points
  (x, y, force, azimuth, altitude, timestamp), pointKind, extended
  dictionary. pointKind matters: .sampled (imported .note curvespoints,
  float32 x,y pairs) vs .control (PencilKit B-spline control points).
  Treating one as the other changes stroke shape, so the kind is stored
  and renderers must honour it.
- Coordinates are page points, origin top-left of the page, with page
  width/height stored on the page. No screen-pixel coordinates are ever
  stored, so iPhone and iPad notes stay aligned to the same page.
- formatVersion = 1. NoteFormatMigration.migrateIfNeeded is a skeleton
  that passes v1 through unchanged and refuses newer versions instead
  of silently reinterpreting them. A future v2 must add a branch here
  and keep a v1 sample for regression.

Performance / power rules, enforced in Store.swift and the views:
- File parsing, thumbnail generation and PDF loading run off the main
  thread (DocumentStore ioQueue, qos .utility; PDF pages render one
  page at a time on a background task).
- The notebook list loads manifest.json + thumb.png only, never
  pages.json. Full strokes load only when a note is opened.
- The canvas redraws only on PencilKit drawing-change callbacks.
  No timer, no polling, no continuous rendering loop.
- Thumbnails and exports are one-shot jobs. No background rendering.
- Large files are lazy: PDF pages render one at a time, images load
  per page, the importer streams zip entries (store-only) instead of
  holding a whole backup in memory.

## 2. Project skeleton

- Project root on the iMac: ~/gemini/app_music/InkNote
  (checked absent before creation; AT Music at
  ~/gemini/app_music/AT-Music-main was not touched).
- Xcode project is generated, not hand-edited: tools/generate_project.py
  scans Sources/*.swift and writes InkNote.xcodeproj/project.pbxproj
  with deterministic IDs. Re-run it after adding a source file.
- Sources (13 files, see the project file): InkNoteApp, CanonicalModel,
  BPlist, NoteImporter, FormulaEvaluator, FutureServices, Store,
  PencilCanvas, PaperTemplateView, NotebookListView, NoteEditorView,
  PDFNoteView, ImportView.
- Local git only: `git init` in the project root, no remote, no push
  without explicit user approval.

## 3. First-version UI (what is built)

- Notebook/folder list: create note, create folder, rename note,
  delete note (with confirmation; an imported original .note is never
  deleted), open note. List rows show a thumbnail loaded from thumb.png
  on a background task, or a placeholder when there is none.
- Editor: PencilKit canvas + tool picker, page previous/next/add,
  Save, paper templates drawn in code (blank / lines / grid / dotted).
  The canvas is shown at 1:1 page points inside a ScrollView, so canvas
  coordinates are canonical page coordinates on both iPhone and iPad.
- PDF notes: the original PDF is rendered one page at a time to an
  image on a background queue, the PencilKit canvas overlays that image
  at exactly the same size, and export composites the same page image
  + the same drawing image into a new PDF. Display and export therefore
  share coordinates.
  - Known v1 limitation, stated honestly: the exported PDF is rendered
    (raster), not a vector ink annotation. Vector ink export is future
    work and must not be claimed for v1.
- Import view: pick a .note file, parse on a background queue, report
  curve count, point count, paper size and PDF presence, then save a
  canonical note. Media objects, audio recordings and the handwriting
  index are not parsed in v1; the result screen says so.

## 4. .note importer — offline validation (Mac, Swift, no device)

Samples used (Muse machine, not a fresh 445 MB pull from the NAS):
- small-20251216.note — blank note.
- medium-20251213.note — handwriting note.
- pdf-22222.note — PDF note.

Why a custom parser: PropertyListSerialization returns keyed-archiver
UIDs as the private CFKeyedArchiverUID type, which Swift cannot safely
read. Sources/BPlist.swift therefore parses the documented bplist00
format directly (null/bool/int/real/date/data/string/UID/array/dict)
and represents a UID as an index. No private API is used.

ZIP handling: all three samples use the store method (compression 0)
for every entry. Sources/NoteImporter.swift includes a minimal
store-only ZIP reader and refuses deflated entries with a clear error
instead of silently dropping them.

Validation results: verified on the iMac with the Swift importer
itself (not with Python alone). See section 4.1 for the real output.

### 4.1 Validation run (Mac, 2026-10-26, exit 0, RESULT PASS)

- Command: swiftc Sources/CanonicalModel.swift Sources/BPlist.swift
  Sources/NoteImporter.swift Sources/FormulaEvaluator.swift
  Validation/main.swift -o /tmp/ImporterValidation && run against
  the three samples in ValidationSamples/.
- Output (verbatim, key lines):
  - small-20251216.note: name=笔记 2025年12月16日, curves=0,
    points=0, pdfs=0, paper=letter, orientation=portrait,
    sessionFormat=9, pageSize=612.0x792.0, summedPoints=0, PASS.
  - medium-20251213.note: name=笔记 2025年12月13日, curves=125,
    points=3362, pdfs=0, paper=letter, orientation=portrait,
    sessionFormat=9, pageSize=612.0x792.0, summedPoints=3362, PASS.
  - pdf-22222.note: name=22222 (2), curves=3, points=30, pdfs=1,
    paper=a4, orientation=portrait, sessionFormat=9,
    pageSize=595.0x842.0,
    pdfFileName=7E00EDFD-4451-45F0-9707-F092E39BCD25.pdf,
    pdfBytes=1060159, summedPoints=30, PASS.
  - Typed formula check in the same run: 2+3*4 = 14.0, as expected.
  - Final line: RESULT PASS, VALIDATOR_EXIT:0.
- Two real bugs found and fixed during this run (recorded so they
  are not reintroduced):
  1. Swift Data slices preserve original indices. Indexing a slice
     with 0-based offsets traps with SIGTRAP (exit 133). Fix: copy
     every slice to a fresh Data (BPlistParser init, .data values,
     SimpleZipReader entries) before 0-based indexing.
  2. BPlist extended-length counts are unsigned. Using a signed read
     turned counts >= 128 negative and trapped on
     Range(lowerBound > upperBound). This only showed up on the PDF
     sample, which has a longer data/string object. Fix: read counts
     as unsigned in BPlistParser.count().

## 5. Build verification (Mac, xcodebuild, unsigned)

- Command: xcodebuild -project InkNote.xcodeproj -scheme InkNote
  -sdk iphoneos -destination generic/platform=iOS
  CODE_SIGNING_ALLOWED=NO
- Result (2026-10-26, Xcode 26.6, macOS 26.3.1, arm64):
  ** BUILD SUCCEEDED **
  - Built app: DerivedData/InkNote-*/Build/Products/Debug-iphoneos/
    InkNote.app, 1.0 MB (binary InkNote, Info.plist, PkgInfo).
  - No IPA was produced or kept. DerivedData was cleaned after the
    successful build (see below), to respect the ~28 GB free disk.
  - Final build log (/tmp/inknote-build5.log on the iMac) contains no
    error lines and no warning lines in the filtered output.
- Build failures fixed on the way (recorded, not hidden):
  1. PencilCanvas.swift: UIColor.getRed needs CGFloat pointers, not
     Double (RGBAColor is Double-based); fixed with CGFloat temporaries.
     PKInkType does not exist in this SDK; the type is PKInk.InkType.
  2. NotebookListView.swift: a single large SwiftUI body timed out the
     type checker. Fixed by breaking the body into small computed
     properties and a separate NoteRowView, and by making NoteManifest
     Identifiable (its id is already its UUID).
  3. An orientation warning ("all interface orientations must be
     supported unless the app requires full screen") was fixed by
     setting INFOPLIST_KEY_UIRequiresFullScreen = YES in the generated
     project (a note app is full-screen by nature).
- "Build succeeded" means the code compiles. It does NOT mean handwriting
  feel, latency, PDF alignment or import rendering have been verified
  on a device. Those are device-checklist items in section 6, and they
  remain unverified until the user runs them.
- DerivedData cleanup: after the successful build, the InkNote
  DerivedData directory was removed with rm -rf. The project sources,
  the generated project file and this log remain; the .app bundle is
  not kept as a deliverable in v1.

## 6. Device verification checklist (for the user, on real devices)

Not verified by the builder. Please run each item and report back:

1. iPad — New note, handwriting: does the pen follow the tip with no
   visible lag or stutter? Try fast strokes and slow pressure strokes.
2. iPad — Long writing session (10+ minutes): any heat build-up or
   unusual battery drain beyond normal note-taking? Note subjective
   feel; no instrumented power measurement was run in v1.
3. iPad — PDF note: import the pdf-22222 sample, annotate a PDF page,
   export, and check the exported PDF: is every annotation on the same
   place as on screen, page by page?
4. iPad + iPhone — Imported handwriting note: open the medium sample
   after import. Is the stroke count (125 curves) and the position of
   the strokes on the page the same as in the original note?
5. iPhone — List and editor: create, rename and delete a note; open a
   note and write on it. Are coordinates aligned to the page (no drift
   when scrolling), and does the list stay fast with several notes?
6. iPhone + iPad — Page switching: add a page, write on page 2, go back
   to page 1, return to page 2. Is page 2's handwriting still there?

## 7. Explicitly NOT in v1

- NAS sync (interface only, FutureServices.NASSyncPlaceholder).
- Audio recording + AI transcription (interface only).
- Handwriting-to-text recognition (interface only).
- Handwritten formula recognition (interface only; typed formulas
  work via FormulaEvaluator).
- Vector ink PDF export (v1 export is rendered/raster, see section 3).
- Smart Script / Math Notes integration: those are system-app
  features with no public third-party API, and are not embedded.
- Any use of another app code, assets, icons or trademarked name;
  any use of the crack-injection dylibs found in the analysed IPA;
  any distribution of an IPA; any GitHub push.

## 8. Change log

- v1 (this build): canonical model v1, project skeleton, notebook
  management, PencilKit editor, PDF annotation + rendered export,
  .note importer prototype with Mac offline validation, this log.

## 9. Release 0.1.0 build 1 — GitHub Actions unsigned IPA

- Repository: https://github.com/ashoru/InkNote — created public.
  AT Music is also public, and this code contains no private note
  samples, so public follows that convention. The repository can be
  switched to private at any time; that change does not affect the IPA.
- Version in the build: MARKETING_VERSION 0.1.0,
  CURRENT_PROJECT_VERSION 1, bundle id com.ashoru.inknote,
  minimum iOS 18.0, iPhone + iPad. The version was changed from the
  v1 build's 1.0 to 0.1.0 in tools/generate_project.py before release;
  the generated project was regenerated and verified.
- Workflow: .github/workflows/build-unsigned-ipa.yml, adapted from
  AT Music's unsigned-IPA workflow (read-only reference, AT Music was
  not modified). Differences from AT Music: it runs
  tools/generate_project.py instead of XcodeGen, reads the version
  from InkNote.xcodeproj/project.pbxproj instead of project.yml, and
  does not copy AT Music's version, CHANGELOG or signing setup.
- Push model, stated plainly: GitHub main is a snapshot history.
  The repository was empty, and the Git Data API cannot create blobs
  in an empty repository (409 "Git Repository is empty"), and git
  over HTTPS from a non-interactive session cannot read the Mac
  keychain. So the first commit on GitHub was created with the
  Contents API (README only, commit 2a1ca8e4c5803508515b674052267e8a7accef43),
  then the full v1 tree was pushed with the Git Data API as a
  snapshot commit eba5e3bbf4d5bb99865fb67e77f71f06deb962a2, whose
  tree sha 0eac33857282a1e5f8f969bdfec4614788a03eb2 exactly matches
  the Mac local commit c912aa6b9b349f2d850231677b5e80b3aede1235.
  Mac main stays at c912aa6; GitHub main is not the same commit sha,
  but the file tree is identical. Future pushes use the same
  snapshot model (tree verification, GitHub HEAD as parent), not a
  claim that Mac and GitHub commit shas match.
- Private samples excluded, verified before commit: git status was
  checked item by item. Validation/ and ValidationSamples/ (which
  contain .note samples), and any .note, .ipa, .app file are in
  .gitignore and were not staged. The staged list was 19 files:
  workflow, .gitignore, this log, project.pbxproj, README, 13 Swift
  sources, tools/generate_project.py. This log records only sample
  statistics (curve counts, point counts), never note body text.
- Actions run: workflow_dispatch, run 40312043075,
  https://github.com/ashoru/InkNote/actions/runs/40312043075,
  conclusion success. "Triggered" was not accepted as complete; the
  run was polled to completed/success.
- Release: https://github.com/ashoru/InkNote/releases/tag/v0.1.0-build1,
  name "InkNote 0.1.0 (build 1)", not a draft, not a prerelease.
  Assets: InkNote-0.1.0-build1-unsigned.ipa (280329 bytes) and
  InkNote-0.1.0-build1-unsigned.ipa.sha256.
- IPA verification, done locally after download from the Release
  (not from the build log alone): shasum -c on the .sha256 file
  passed, SHA-256
  d50633fb5f7955ddd36baa1ac17a8218986aabaf015f6a8906f8bd27da638bc8.
  Unpacked Info.plist: CFBundleIdentifier com.ashoru.inknote,
  CFBundleShortVersionString 0.1.0, CFBundleVersion 1,
  MinimumOSVersion 18.0, CFBundleExecutable InkNote,
  UIDeviceFamily [1, 2]. Main binary Payload/InkNote.app/InkNote,
  1031160 bytes, present. The local IPA copy was kept only for this
  verification in /tmp and is not a deliverable; DerivedData and
  temporary IPA copies on the Mac were cleaned after the build.
- Note on section 7: "any GitHub push" was the v1 build scope. This
  section supersedes it for this release only: the push above is the
  release push, and no other IPA was distributed.
- Sideloading note (for the device checklist): the IPA is unsigned.
  Downloading it does not install it on a device. Sign it yourself,
  for example in Xcode with your own Apple ID, or with a sideloading
  tool you trust, before installing it on an iPhone or iPad. Do not
  present the Release download as install-and-run.
