import Foundation

// MARK: - Display-only localization mappings
//
// Storage values never change here. The folder key "Unsorted" stays
// "Unsorted" on disk and in every filter / Picker tag; only the text
// shown to the user is mapped through the String Catalog. That is why
// an old note whose manifest folder is "Unsorted" still filters into
// the list after this change: the filter compares storage values,
// never display strings. The same rule holds for note names (a name
// is user data, shown verbatim, never re-localized) and for the
// source key "imported-note" (shown as a localized word, stored as-is).
// Paper size / orientation come from the imported file as raw codes
// ("a4", "letter", "portrait", "landscape"); only their display form
// is mapped, the summary values themselves are untouched.

public enum DisplayStrings {
    public static func folderDisplayName(_ folder: String) -> String {
        if folder == "Unsorted" {
            return String(localized: "Unsorted")
        }
        return folder
    }

    public static func sourceDisplayName(_ source: String) -> String {
        if source == "imported-note" {
            return String(localized: "Imported")
        }
        return "InkNote"
    }

    public static func paperSizeDisplay(_ size: String) -> String {
        switch size {
        case "a4": return "A4"
        case "letter": return String(localized: "Letter")
        default: return size
        }
    }

    public static func orientationDisplay(_ orientation: String) -> String {
        switch orientation {
        case "portrait": return String(localized: "Portrait")
        case "landscape": return String(localized: "Landscape")
        default: return orientation
        }
    }
}
