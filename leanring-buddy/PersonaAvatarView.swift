//
//  PersonaAvatarView.swift
//  leanring-buddy
//
//  Renders a `PersonaAvatar` as a circular thumbnail. Three cases:
//  initials over a colored fill, an SF Symbol over a colored fill, or
//  a user-uploaded image clipped to a circle. The same view is used
//  by the radial wheel picker, the cursor orb (in MysticalOrbView),
//  and the panel persona row, so the visual identity stays consistent
//  everywhere a persona shows up.
//

import SwiftUI

struct PersonaAvatarView: View {
    let avatar: PersonaAvatar

    /// Outer diameter of the circular avatar. Set to whatever size the
    /// container needs — the symbol/text inside scales proportionally.
    let diameter: CGFloat

    /// Whether to draw a soft white ring around the circle. Used by the
    /// wheel picker for the highlighted spoke and by the cursor orb so
    /// the avatar reads cleanly over busy desktop wallpapers.
    var showsRing: Bool = false

    /// Color of the ring when `showsRing` is true. Defaults to white at
    /// 70% opacity which works on both light and dark wallpapers.
    var ringColor: Color = Color.white.opacity(0.7)

    /// Stroke width of the optional ring. Tuned to match the wheel-
    /// picker highlight at 56pt diameter; scales with diameter for
    /// other sizes so the ring stays visually proportional.
    var ringLineWidth: CGFloat? = nil

    var body: some View {
        ZStack {
            backgroundCircle
            foregroundContent
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay(ringOverlay)
    }

    // MARK: - Background fill

    /// Solid colored circle behind the avatar foreground. For the
    /// `.imageFile` case this is hidden behind the image so it only
    /// matters when the file is missing or still loading.
    @ViewBuilder
    private var backgroundCircle: some View {
        switch avatar {
        case .initials(_, let hexColor),
             .systemSymbol(_, let hexColor):
            Circle()
                .fill(Color(hexString: hexColor) ?? Color.gray)
        case .imageFile:
            Circle()
                .fill(Color.gray.opacity(0.3))
        }
    }

    // MARK: - Foreground content

    /// The actual avatar mark — initials text, a centered symbol, or
    /// the image file. Sized relative to `diameter` so swapping
    /// between cases stays visually consistent at any size.
    @ViewBuilder
    private var foregroundContent: some View {
        switch avatar {
        case .initials(let text, _):
            Text(initialsText(text))
                .font(.system(size: diameter * 0.42, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        case .systemSymbol(let symbolName, _):
            Image(systemName: symbolName)
                .font(.system(size: diameter * 0.45, weight: .semibold))
                .foregroundColor(.white)
        case .imageFile(let filename):
            personaImageFromDisk(filename: filename, diameter: diameter)
        }
    }

    /// Truncates initials to two characters max — three or four-letter
    /// initials don't fit cleanly inside a small circle.
    private func initialsText(_ text: String) -> String {
        guard text.count > 2 else { return text }
        return String(text.prefix(2))
    }

    // MARK: - Optional ring overlay

    @ViewBuilder
    private var ringOverlay: some View {
        if showsRing {
            Circle()
                .stroke(ringColor, lineWidth: ringLineWidth ?? max(2, diameter * 0.04))
        }
    }
}

// MARK: - Image loading

/// Loads a persona's `.imageFile` avatar. Tries the app bundle first
/// (so photos shipped with the binary — like the team's faces — render
/// without any setup), then falls back to a user-installed file in
/// Application Support. This means a teammate can be added two ways:
/// drop a JPEG into the `leanring-buddy/` source dir for the next
/// build, OR drop one into Application Support for hot-swapping
/// without rebuilding.
@ViewBuilder
private func personaImageFromDisk(filename: String, diameter: CGFloat) -> some View {
    if let nsImage = PersonaImageLoader.bundledOrDiskImage(forFilename: filename) {
        Image(nsImage: nsImage)
            .resizable()
            .scaledToFill()
            .frame(width: diameter, height: diameter)
    } else {
        // File missing in both locations — fall back to a generic
        // person glyph so the wheel still renders cleanly.
        Image(systemName: "person.fill")
            .font(.system(size: diameter * 0.5, weight: .semibold))
            .foregroundColor(.white.opacity(0.7))
    }
}

/// Resolves persona image filenames to absolute on-disk URLs. Looks in
/// `~/Library/Application Support/com.learning-buddy.clicky/personas/`
/// — the same directory PersonaStore will use once it grows past the
/// in-memory sample data.
enum PersonaImageLoader {
    /// Subdirectory where user-installed persona images live (the
    /// hot-swap path that doesn't require a rebuild). Same convention
    /// as the existing TasteProfileStore.
    private static let applicationSupportSubdirectoryName = "com.learning-buddy.clicky"
    private static let personasSubdirectoryName = "personas"

    /// Resolves a persona image filename (e.g. `magda.jpeg`) by trying
    /// three locations in order: (1) Asset Catalog by base name, since
    /// images dropped into Assets.xcassets get looked up that way;
    /// (2) loose Resources inside the app bundle, for files placed
    /// directly in `leanring-buddy/` and picked up via the synchronized
    /// folder reference; (3) Application Support `personas/`, for hot-
    /// swap photos installed without rebuilding. Returns nil when none
    /// of those have the file.
    static func bundledOrDiskImage(forFilename filename: String) -> NSImage? {
        let filenameAsURL = URL(fileURLWithPath: filename)
        let baseName = filenameAsURL.deletingPathExtension().lastPathComponent
        let fileExtension = filenameAsURL.pathExtension.isEmpty ? nil : filenameAsURL.pathExtension

        if let assetCatalogImage = NSImage(named: baseName) {
            return assetCatalogImage
        }

        if let bundledURL = Bundle.main.url(forResource: baseName, withExtension: fileExtension),
           let bundledImage = NSImage(contentsOf: bundledURL) {
            return bundledImage
        }

        if let diskURL = applicationSupportImageURL(forFilename: filename),
           let diskImage = NSImage(contentsOf: diskURL) {
            return diskImage
        }

        return nil
    }

    /// Returns the absolute URL where a hot-swap persona image lives in
    /// Application Support. Does NOT check existence — that's the
    /// loader's job.
    private static func applicationSupportImageURL(forFilename filename: String) -> URL? {
        guard let applicationSupportDirectoryURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }

        return applicationSupportDirectoryURL
            .appendingPathComponent(applicationSupportSubdirectoryName, isDirectory: true)
            .appendingPathComponent(personasSubdirectoryName, isDirectory: true)
            .appendingPathComponent(filename, isDirectory: false)
    }
}
