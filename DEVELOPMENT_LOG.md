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

## 10. Fix 0.1.1 build 2 — notes that could not be opened (Loading note forever)

- User report (device, 2026-10-26): a newly created note (ttt) appeared
  in the list but opening it showed only "Loading note..." forever.
  This is accepted as fact; the v1 build passing does not contradict it.
- Root cause, one sentence: saveDocument wrote manifest.json with
  JSONEncoder dateEncodingStrategy .iso8601, but loadManifests,
  loadDocument and renameNote all read with a bare JSONDecoder whose
  default date strategy is secondsSince1970, so decoding an ISO8601
  date string always failed.
- Consequence chain: createNote saved in memory, so the list showed
  ttt; opening it called loadDocument, decoding failed, completion
  was nil, NoteDestinationView had no error state and its .task ran
  only once, so it spun forever. After a restart, loadManifests
  skipped every saved note, so the list could go empty. The files on
  disk were never deleted and no note data was lost; fixing the
  decoder makes them readable again.
- Fix 1, shared codec (CanonicalModel.swift): new InkNoteCodec with
  one JSONEncoder (.sortedKeys, .iso8601) and one JSONDecoder
  (.iso8601), Foundation-only so the Mac validation tool uses the
  exact same codec as the app. Never reintroduce a bare JSONDecoder
  or JSONEncoder for InkNote files.
- Fix 2, Store.swift: all 7 codec call sites now use InkNoteCodec:
  loadManifests (1), loadDocument (manifest + pages, 2),
  saveDocument (manifest + pages, 2), renameNote (decode + encode, 2).
  renameNote previously also wrote dates back with a bare encoder
  (numbers), which would have failed the next ISO8601 read; it now
  uses the shared encoder. A grep of Sources/ after the fix shows no
  bare codec call site outside the InkNoteCodec definition itself.
- Fix 3, NotebookListView NoteDestinationView: cache-first (use
  store.documents[noteID] if already in memory, no disk wait); on
  disk-load failure show "Failed to load note" + a Retry button that
  increments an attempt counter and really re-runs the load via
  .task(id: attempt); a failed retry does not crash and does not
  spin forever. The failure text states the file was not deleted.
- Regression validation, Mac offline, exit 0, RESULT PASS:
  a Swift script compiled with CanonicalModel.swift only, using
  InkNoteCodec, wrote a manifest (name ttt, folder tt) + 2 pages
  with a 2-point stroke, read them back, and asserted name, both
  dates, page count and stroke points; it also read an old-format
  ISO8601 manifest file and asserted it opens; it also asserted
  the default secondsSince1970 decoder fails on that same file,
  confirming the root cause. Two script bugs found and fixed during
  validation itself (top-level code must live in main.swift when
  compiling several files; a test timestamp was 2025, not 2026) —
  neither was an app bug.
- Build: iMac xcodebuild unsigned, ** BUILD SUCCEEDED **, Xcode 26.6.
  DerivedData for InkNote was cleaned after the build.
- Version: 0.1.1 build 2 (MARKETING_VERSION 0.1.1,
  CURRENT_PROJECT_VERSION 2, bundle com.ashoru.inknote, minimum
  iOS 18.0). This section is the fix record; the release record is
  section 11.
- Device retest (not yet done by the builder, must be done by the
  user after installing the new build): 1) old note ttt reappears
  in the list after restart; 2) open ttt, it opens instead of
  spinning; 3) write in it, close and reopen, writing is still
  there; 4) create a new note, open it, write, restart the app,
  open it again. A retry button appearing at all means the load
  still failed and must be reported, not worked around silently.

## 11. Release 0.1.1 build 2 — fix published

- Fix pushed first, then released (same snapshot model as section 9):
  Mac commit 58953636a08ffa42e23fd5f412327bda61583d50, tree
  66d60b140541830cbc74d29c75319baeb68a9060; GitHub commit
  0b7977cf1c5981821412d1e9b76953c01971aad2 with the identical tree.
  Mac and GitHub commit hashes differ, file trees are identical.
  Changed files (6): DEVELOPMENT_LOG.md, project.pbxproj,
  Sources/CanonicalModel.swift, Sources/NotebookListView.swift,
  Sources/Store.swift, tools/generate_project.py. No Validation,
  ValidationSamples, .note, .ipa or .app file was staged.
- Actions run: workflow_dispatch, run 40317713544, conclusion
  success (polled to completed, not merely triggered).
- Release: https://github.com/ashoru/InkNote/releases/tag/v0.1.1-build2,
  name "InkNote 0.1.1 (build 2)", not a draft, not a prerelease.
  Assets: InkNote-0.1.1-build2-unsigned.ipa (286145 bytes) and
  InkNote-0.1.1-build2-unsigned.ipa.sha256.
- IPA verification, done locally after download from the Release
  (not from the build log alone): shasum -c on the .sha256 file
  passed, SHA-256
  316ca47356ba8b22e767ba85092fe5b7002e8c2f0f80f896c33b0c19a91e5c19.
  Unpacked Info.plist: CFBundleIdentifier com.ashoru.inknote,
  CFBundleShortVersionString 0.1.1, CFBundleVersion 2,
  MinimumOSVersion 18.0, CFBundleExecutable InkNote,
  UIDeviceFamily [1, 2]. Main binary Payload/InkNote.app/InkNote,
  1063872 bytes, present. The local IPA copy was kept only for this
  verification in /tmp and was deleted afterwards.
- Sideloading note, unchanged from section 9: the IPA is unsigned.
  Downloading it does not install it on a device. Sign it yourself,
  for example in Xcode with your own Apple ID, or with a sideloading
  tool you trust, before installing it on an iPhone or iPad.
- What this build fixes on device (to be confirmed by the user, not
  claimed by the builder): saved notes that previously failed to
  decode now open; a load failure now shows an error with a real
  Retry instead of spinning forever; notes already on disk were
  never deleted and become readable again after this update.

## 12. Update 0.1.2 build 3 — localization (zh-Hans + en) and restrained UI polish

- User feedback (device, 2026-10-26): the whole app was hardcoded
  English and the interface looked too plain. Asked for: a Chinese
  version, both Chinese and English supported, and interface polish.
  Scope of this build is exactly that. AT Music was not touched.
  Nothing in this build changes the canonical model, the store, the
  importer logic, or any file format.

### 12.1 Localization: String Catalog, system language follows

- New file Localizable.xcstrings at the project root, 76 keys, with
  en and zh-Hans translations for every key. The app follows the
  system language; there is no in-app language switcher in this build.
- Static labels use string literals, which SwiftUI treats as
  LocalizedStringKey and resolves through the catalog: list toolbar
  and alerts, editor and PDF toolbars, import view, iPad detail
  placeholder, load-failure and retry states, empty states.
- Programmatic strings use String(localized:) with a format, then
  String(format:), and are shown verbatim so they are never
  re-localized as keys: "Page %lld of %lld" / "PDF page %lld of %lld"
  (zh: "第 %lld 页，共 %lld 页" / "PDF 第 %lld 页，共 %lld 页"),
  "Notes in %@", import result lines (Imported / Curves / Points /
  Paper / Session format / PDF files), and all LocalizedError texts
  in BPlist, NoteImporter, FormulaEvaluator and FutureServices.
  No Chinese/English mixing: every interpolated value goes through a
  catalog format, including curve/point counts.
- Dates keep the system style: Text(date, style: .date) in list rows
  was already system-localized and is unchanged. No hand-built
  English month names exist anywhere.
- User data is never localized: note names, user-created folder
  names, imported file names and paper codes are shown with
  Text(verbatim:) (the old code passed some of them through Text(String),
  which would have re-localized a name that happened to match a
  catalog key). Paper size / orientation codes from an imported file
  are display-mapped only ("a4" -> "A4", "letter" -> "Letter",
  "portrait" -> "竖向", "landscape" -> "横向"); the stored summary
  values are untouched.
- Folder mapping decision (display layer only, storage untouched):
  the stored folder key stays "Unsorted" on disk, in every filter
  comparison and in every Picker tag. Only the displayed word is
  mapped ("Unsorted" -> "未分类" in zh, "Unsorted" in en) via
  DisplayStrings.folderDisplayName. A user-created folder such as
  "tt" is displayed exactly as typed. An empty new-note name takes
  the current system language's default at creation time
  ("Untitled" / "未命名"); that is a name, not a filter key, so
  existing notes keep their names when the language changes.
  Why old notes cannot be lost: the list filter compares
  manifest.folder against the selected storage value, never against
  the display word, so a language switch cannot orphan a note.
  Validation for this, Mac offline, exit 0, 7 checks PASS: an old
  manifest (name ttt, folder "Unsorted") decodes unchanged, filters
  in under the storage value "Unsorted", a "tt" folder displays
  unchanged, and the display functions route through the catalog
  lookup. The zh display word itself is proven from the built app
  bundle, not from this CLI run (the CLI tool has no catalog bundle
  and correctly falls back to the English key): the built bundle's
  zh-Hans.lproj/Localizable.strings maps "Unsorted" => "未分类"
  (see 12.5).
- Two user-visible English leaks found by a literal scan and fixed
  here, not in the original task list: the importer's fallback note
  name "Imported Note" (shown in the list when a .note has no name)
  and the "Missing $objects/$top in Session.plist" detail wrapped
  into sessionParseFailed. Both now go through the catalog
  ("导入的笔记" / "Session.plist 中缺少 $objects/$top", archive
  key names kept verbatim).
- Hardcoded-English grep after the change (Sources/): every UI
  literal is either a catalog key (verified: all String(localized:)
  keys exist in the catalog, and every Text/Button/Label/Section/
  Picker/TextField/ProgressView literal was checked against it) or
  one of these allowed exceptions, listed here so a future grep is
  not mistaken for a regression: app name "InkNote"; storage keys
  "Unsorted", "inknote", "imported-note" (display-mapped, never
  shown raw except through DisplayStrings); file/format tokens
  (".note", ".pdf", "a4", "letter", "portrait", "landscape",
  bplist/ZIP/plist key names, paper template codes); SF Symbol
  names; parser single-character tokens; the internal save-failure
  print in Store.swift (log only, never shown in UI).

### 12.2 Interface polish (native components only)

- Toolbars and actions use Label (SF Symbol + system text style):
  New Note square.and.pencil, Folder folder, Import
  square.and.arrow.down, Previous chevron.left, Next chevron.right,
  Add Page plus, Save checkmark, Export PDF square.and.arrow.up,
  Rename pencil, Delete trash, Retry arrow.clockwise.
  Save icon choice, recorded deliberately: checkmark, not
  tray.and.arrow.down. Saving here is an in-place persist, not a
  download and not an export to another location (export already
  uses square.and.arrow.up, import uses square.and.arrow.down), so
  a download-style icon would confuse save with import/export.
- Next buttons are new in this build: the paper editor and the PDF
  view previously had only Previous (forward was only possible via
  Add Page in the paper editor, and not at all in the PDF view).
  Both now have Previous / Next with correct disabled states.
- List: thumbnails 44x56 -> 56x72 (one step up, inside the 60x76
  budget so the list cannot stutter), still loaded lazily per row
  from thumb.png on a background task; rows show name, localized
  source (Imported / InkNote) and system-localized modified date.
  Added .searchable: it filters only the in-memory manifests by
  name, never reads pages.json, so search cannot slow down on large
  notes. Empty states are real states, not a grey line: the list
  shows an icon + "No notes yet" + New Note button (or "No matching
  notes" while searching), and the iPad detail placeholder shows an
  icon + sentence + New Note button.
- Editor and PDF view: the page now sits on the system grouped
  background with a margin and a soft shadow, so the page has depth
  in both light and dark mode. The chrome follows the system; the
  paper itself stays white content in both modes and is never
  painted dark. Save feedback is transient: "Saved" clears itself
  after 1.5 seconds (one-shot Task sleep guarded by a token, not a
  timer or poll) instead of occupying a permanent row. The page
  indicator stays in the toolbar row.
- iPad detail limitation, stated honestly: the detail pane's New
  Note button creates a note in the Unsorted folder, which then
  appears in the list to open; it does not jump straight into the
  editor, because the detail pane is not a navigation destination
  in v1. Wiring selection through the split view is future work,
  not claimed here.
- Performance / power rules, unchanged and re-checked: the list
  still loads manifests + thumbnails only; search is memory-only;
  thumbnails and PDF pages are still lazy and background-loaded;
  no polling, no animation loop, no large-area blur was added
  (the page shadow is a static one-shot effect, not a live blur).

### 12.3 App icon (original artwork, drawn in code)

- New script tools/make_appicon.swift (kept in tools/, not in
  Sources/, so the project generator does not compile it into the
  app). It draws with CoreGraphics only — no AppKit window server —
  so it runs over SSH: a blue-to-teal gradient field, a white ruled
  paper sheet, and an amber pencil leaning across it. No other
  app's icon, shape or trademark is copied.
- Output: Assets.xcassets/AppIcon.appiconset with Contents.json
  listing 18 sizes (iPhone, iPad, App Store) and one PNG per size,
  all scaled from the 1024x1024 master with sips (AppIcon-1024.png
  for the store slot, e.g. 180x180 for 60pt @3x, 167x167 for
  83.5pt @2x). A first attempt that pointed every slot at the
  single 1024 file built but produced actool size warnings for
  every slot; the per-size files removed all of them (see 12.5).
  The unreferenced 1024 draft file was removed from the set.
- tools/generate_project.py now includes a resources build phase:
  Assets.xcassets and Localizable.xcstrings are file references in
  the main group and in PBXResourcesBuildPhase, knownRegions gains
  zh-Hans, and the target sets ASSETCATALOG_COMPILER_APPICON_NAME
  to AppIcon. The Actions workflow already regenerates the project
  from this script, so the release build picks the resources up
  with no workflow change.

### 12.4 Files changed in this build

- New: Sources/DisplayStrings.swift (display mappings only),
  Localizable.xcstrings (76 keys), Assets.xcassets (icon set),
  tools/make_appicon.swift.
- Modified: NotebookListView, NoteEditorView, PDFNoteView,
  ImportView, InkNoteApp, BPlist, FormulaEvaluator,
  FutureServices, NoteImporter (error texts only), plus
  tools/generate_project.py and the generated project.pbxproj.
- Unchanged: CanonicalModel, Store, PencilCanvas,
  PaperTemplateView, Validation/, ValidationSamples/ (never staged).

### 12.5 Build and validation (Mac, xcodebuild, unsigned)

- Version: 0.1.2 build 3 (MARKETING_VERSION 0.1.2,
  CURRENT_PROJECT_VERSION 3, bundle com.ashoru.inknote, minimum
  iOS 18.0). The generated pbxproj was grepped after regeneration:
  both version values appear in both configurations, and
  Assets.xcassets + Localizable.xcstrings are in the resources phase.
- Clean rebuild, Xcode 26.6, macOS 26.3.1, arm64:
  ** BUILD SUCCEEDED **, exit 0, no error lines. Icon size
  warnings are gone after the per-size fix. The only remaining
  warning line in the log is an AppIntents metadata-processor note
  ("Metadata extraction skipped. No AppIntents.framework
  dependency found"), which is tool noise about a framework the
  app does not use, not an app warning.
- Built bundle checks (not from the build log alone): Info.plist
  CFBundleIdentifier com.ashoru.inknote,
  CFBundleShortVersionString 0.1.2, CFBundleVersion 3,
  MinimumOSVersion 18.0; Assets.car present and the app-icon PNGs
  ship in the bundle; en.lproj and zh-Hans.lproj each contain a
  compiled Localizable.strings with 76 entries, spot-checked with
  plutil (zh: "New Note" => "新建笔记", "Page %lld of %lld" =>
  "第 %lld 页，共 %lld 页", "Unsorted" => "未分类",
  "Previous" => "上一页"; en values are identity). Format
  placeholders (%lld, %@) survive compilation intact.
- Importer regression, same three samples, exit 0, RESULT PASS:
  small 0 curves / 0 points, medium 125 / 3362, pdf 3 / 30 with 1
  PDF, formula 2+3*4 = 14. The error-text localization did not
  change any parse result.
- Folder validation, exit 0, 7 checks PASS (see 12.1).
- Two real mistakes found and fixed during this build itself:
  1. The single-PNG icon set warned on every slot (see 12.3).
  2. The folder validation script first failed to compile with
     "expressions are not allowed at the top level" because only a
     file named main.swift may carry top-level code when several
     files are compiled together — the same pitfall recorded in
     0.1.1. Fixed by compiling the script as main.swift in its own
     directory; it is a /tmp validation script, not repo code.
- DerivedData for InkNote was cleaned after the build, to respect
  the ~28 GB free disk. No IPA was produced or kept locally.

### 12.6 Device retest for 0.1.2 (not verified by the builder)

1. System language Chinese: list, alerts, editor toolbar, PDF
   toolbar, load-failure retry and import result all show Chinese,
   with no English placeholder and no misplaced numbers in the
   page indicator ("第 x 页，共 y 页") or import counts.
2. System language English: the same screens show the English
   texts, and switching the language back does not lose any note.
3. Old note ttt: still listed under the unclassified folder after
   the update (displayed as "未分类" in Chinese), opens, and keeps
   its name.
4. New note with an empty name: created with the current language's
   default name ("未命名" in Chinese, "Untitled" in English).
5. List: search filters by name; empty list and empty search show
   the new empty states; thumbnails look right at the larger size.
6. Editor / PDF: page has a margin and shadow on both light and
   dark mode, paper stays white, Next moves forward, Save shows a
   brief "Saved" that disappears on its own.
7. Home screen: the new icon actually shows (the builder verified
   the icon files ship in the bundle, not how iOS renders them on
   a home screen).
8. iPad detail placeholder: icon + sentence + New Note button;
   tapping New Note creates a note in the unclassified folder,
   visible in the list to open (see the limitation in 12.2).

## 13. Release 0.1.2 build 3 — localization and UI polish published

- Change pushed first, then released (same snapshot model as
  section 9): Mac commit c42cc479d905dc5b87ac617068827dae006d14c6,
  tree 53440cdf8f655dd00cbbfcab4b14bd12e63799ce; GitHub commit
  167b7819c570eb664c95622186eebc170a52c055 with the identical
  tree. Mac and GitHub commit hashes differ, file trees are
  identical. Changed files (32): 15 App Icon PNGs + 2 Contents.json
  files, Localizable.xcstrings, 10 Swift files (9 modified, 1 new
  DisplayStrings.swift), project.pbxproj, this log, and 2 tool
  scripts (generate_project.py, make_appicon.swift). No Validation,
  ValidationSamples, .note, .ipa or .app file was staged. The
  snapshot push script for InkNote lives outside the repo at
  ~/workspace/bin/gh-gitdata-push-inknote.py (adapted from the
  AT Music script; it verifies parent tree equality and new tree
  equality, and uses a dedicated git-ssh wrapper without a hardcoded
  host, since the plain ssh wrapper's hardcoded host breaks git's
  own host argument).
- Actions run: workflow_dispatch, run 40321789624, conclusion
  success (polled to completed, not merely triggered).
  https://github.com/ashoru/InkNote/actions/runs/40321789624
- Release: https://github.com/ashoru/InkNote/releases/tag/v0.1.2-build3,
  name "InkNote 0.1.2 (build 3)", not a draft, not a prerelease.
  Assets: InkNote-0.1.2-build3-unsigned.ipa (490049 bytes) and
  InkNote-0.1.2-build3-unsigned.ipa.sha256.
- IPA verification, done locally after download from the Release
  (not from the build log alone): shasum -c on the .sha256 file
  passed, SHA-256
  aa882042d315645644ca1bdb159d31ab4503a55a1e2e4cc71a340b86b7159e1c.
  Unpacked Info.plist: CFBundleIdentifier com.ashoru.inknote,
  CFBundleShortVersionString 0.1.2, CFBundleVersion 3,
  MinimumOSVersion 18.0, CFBundleExecutable InkNote,
  UIDeviceFamily [1, 2]. Main binary Payload/InkNote.app/InkNote,
  1204424 bytes, present. The bundle also contains en.lproj and
  zh-Hans.lproj and the App Icon PNGs. The local IPA copy was kept
  only for this verification in /tmp and was deleted afterwards.
- Sideloading note, unchanged from section 9: the IPA is unsigned.
  Downloading it does not install it on a device. Sign it yourself,
  for example in Xcode with your own Apple ID, or with a sideloading
  tool you trust, before installing it on an iPhone or iPad.
- What this build changes on device (to be confirmed by the user,
  not claimed by the builder): Chinese and English interfaces that
  follow the system language, with the old-note folder mapping
  keeping every existing note visible; SF Symbols toolbars with
  Previous / Next in both editors; a larger lazy thumbnail, search
  over list manifests, real empty states, page margin + shadow on
  the system grouped background with the paper staying white, a
  transient Save confirmation, and the new App Icon. The device
  retest list is section 12.6.
