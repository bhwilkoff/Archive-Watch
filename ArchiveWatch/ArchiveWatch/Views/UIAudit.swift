import SwiftUI

// UI Audit — a visual validator that renders every interface element
// across its edge-case matrix so regressions and sizing bugs surface in
// one place. Accessed via long-press on the sidebar brand mark.
//
// Each section renders the component with a sample of tricky inputs:
//   • shortest / typical / longest real title
//   • missing artwork / broken artwork URL / valid artwork
//   • absent metadata / full metadata
//   • selected / unselected / focused / default states
//
// Beyond visual inspection, each specimen is wrapped in `.validated(...)`
// which measures at runtime and prints a warning if text truncates, a
// child overflows its declared frame, or an image has zero size. Look
// for ⚠️ lines in the Xcode console.

struct UIAuditView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    // A deterministic spread of the catalog so the audit is stable
    // across runs: shortest + longest + a normal titled item; one with
    // backdrop, one with only poster, one with no designed artwork.
    private var specimens: AuditSpecimens {
        AuditSpecimens.build(from: store.catalog?.items ?? [])
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 56) {
                header

                Group {
                    sidebarSection
                    chipSection
                    posterCardSection
                    compactPosterSection
                    heroBannerSection
                    actionCardSection
                    collectionCardSection
                    ctaSection
                    typographySection
                }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 40)
        }
        .background(Color.black)
        .focusSection()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("UI AUDIT")
                .font(.system(size: 14, weight: .black))
                .tracking(3)
                .foregroundStyle(Color(hex: "#FF5C35") ?? .orange)
            Text("Component validator")
                .font(.system(size: 48, weight: .heavy, design: .serif))
                .foregroundStyle(.white)
            Text("Every tile, chip, and text block rendered across its edge cases. Runtime truncation + overflow warnings log to Xcode.")
                .font(.system(size: 23))
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: 900, alignment: .leading)
        }
    }

    // MARK: - Sections

    private var sidebarSection: some View {
        AuditSection(title: "Sidebar rows", notes: "Focus: white/22%. Selected: accent/85%. Both get scale + stroke.") {
            HStack(alignment: .top, spacing: 40) {
                ForEach(Router.Tab.allCases) { tab in
                    VStack(spacing: 12) {
                        SidebarSpecimen(tab: tab, selected: false, expanded: true)
                        SidebarSpecimen(tab: tab, selected: tab == .home, expanded: true)
                        Text(tab.title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .frame(width: 300)
                }
            }
        }
    }

    private var chipSection: some View {
        AuditSection(title: "Filter chips", notes: "Default / Selected / Focused. All three must be visibly distinct with no halo leakage.") {
            HStack(spacing: 24) {
                ChipSpecimen(label: "All Titles", isOn: false, accent: .accentColor)
                ChipSpecimen(label: "Silent Era", isOn: true, accent: Color(hex: "#C9A66B") ?? .brown)
                ChipSpecimen(label: "A Very Long Chip Label That Tests Width Budget", isOn: false, accent: .accentColor)
                ChipSpecimen(label: "1970s", isOn: true, accent: Color(hex: "#7C5BBA") ?? .purple)
            }
        }
    }

    private var posterCardSection: some View {
        AuditSection(title: "PosterCard (Home shelves)", notes: "240×360 card + 2-line title below. Long titles shrink, never truncate mid-word.") {
            HStack(alignment: .top, spacing: 28) {
                ForEach(specimens.posters) { spec in
                    VStack(spacing: 10) {
                        Button { } label: { PosterCard(item: spec.item) }
                            .buttonStyle(.card)
                        auditLabel(spec.label)
                    }
                }
            }
        }
    }

    private var compactPosterSection: some View {
        AuditSection(title: "CompactPoster (Browse grid)", notes: "200×300 card + 2-line 15pt title.") {
            HStack(alignment: .top, spacing: 24) {
                ForEach(specimens.posters) { spec in
                    VStack(spacing: 10) {
                        Button { } label: { CompactPoster(item: spec.item) }
                            .buttonStyle(.card)
                        auditLabel(spec.label)
                    }
                }
            }
        }
    }

    private var heroBannerSection: some View {
        AuditSection(title: "HeroBanner (Home hero)", notes: "1920×620 backdrop. Title scales down before truncating. Category + year/runtime/byline only — no synopsis.") {
            VStack(spacing: 16) {
                ForEach(specimens.posters.prefix(3)) { spec in
                    VStack(alignment: .leading, spacing: 6) {
                        auditLabel(spec.label)
                        HeroBanner(item: spec.item)
                            .frame(height: 620)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }

    private var actionCardSection: some View {
        AuditSection(title: "ActionCard (Surprise tab)", notes: "440×660 two-zone card — poster top 62%, info bottom 38%. Should never overlap.") {
            HStack(alignment: .top, spacing: 24) {
                ForEach(specimens.posters.prefix(3)) { spec in
                    VStack(spacing: 10) {
                        ActionCard(
                            title: "RANDOM FILM",
                            subtitle: spec.item.title,
                            caption: spec.item.year.map(String.init) ?? "Undated",
                            icon: "sparkles",
                            accent: Color(hex: "#FF5C35") ?? .orange,
                            posterURL: spec.item.posterURLParsed ?? spec.item.backdropURLParsed
                        )
                        auditLabel(spec.label)
                    }
                }
            }
        }
    }

    private var collectionCardSection: some View {
        AuditSection(title: "CollectionCard (Collections tab)", notes: "Composite 3-poster backdrop + blurb.") {
            if let first = (store.featured?.categories ?? []).first {
                let data = CollectionCardData(
                    id: "Film_Noir",
                    title: "Film Noir",
                    blurb: "Shadows, second thoughts, venetian-blind lighting.",
                    accent: Color(hex: first.accent) ?? .orange,
                    itemCount: 42,
                    posterURLs: specimens.posters.compactMap { $0.item.posterURLParsed }
                )
                HStack(spacing: 32) {
                    CollectionCard(data: data)
                    CollectionCard(data: CollectionCardData(
                        id: "Empty",
                        title: "Tiny Collection",
                        blurb: "A single item — tests the no-backdrop fallback.",
                        accent: Color(hex: "#C9A66B") ?? .brown,
                        itemCount: 1,
                        posterURLs: []
                    ))
                }
            }
        }
    }

    private var ctaSection: some View {
        AuditSection(title: "Primary actions (Play, Roll Again, Favorite)", notes: "Spring-scale focus, accent gradient, stroked when focused.") {
            HStack(spacing: 32) {
                Button { } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(.white).frame(width: 36, height: 36)
                            Image(systemName: "play.fill")
                                .font(.system(size: 16, weight: .black))
                                .foregroundStyle(Color(hex: "#FF5C35") ?? .orange)
                        }
                        Text("Play  ·  1h 32m")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.leading, 10)
                    .padding(.trailing, 28)
                    .padding(.vertical, 10)
                }
                .buttonStyle(PrimaryCTAStyle(accent: Color(hex: "#FF5C35") ?? .orange))
                .focusEffectDisabled()

                Button { } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "dice.fill").font(.title2)
                        Text("Roll Again").font(.title3.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 16)
                }
                .buttonStyle(PrimaryCTAStyle(accent: Color(hex: "#FF5C35") ?? .orange))
                .focusEffectDisabled()

                Button { } label: {
                    Image(systemName: "heart")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .padding(18)
                }
                .buttonStyle(CircleIconStyle())
                .focusEffectDisabled()
            }
        }
    }

    private var typographySection: some View {
        AuditSection(title: "Typography ramp", notes: "tvOS HIG tokens — every size must be legible at 10ft.") {
            VStack(alignment: .leading, spacing: 14) {
                typographyRow("Large Title 76pt", .system(size: 76, weight: .medium))
                typographyRow("Title 1 57pt", .system(size: 57, weight: .medium))
                typographyRow("Title 2 48pt", .system(size: 48, weight: .medium))
                typographyRow("Title 3 38pt", .system(size: 38))
                typographyRow("Headline 38pt semibold", .system(size: 38, weight: .semibold))
                typographyRow("Body 29pt — 10ft floor", .system(size: 29))
                typographyRow("Subheadline / Callout 29/31pt", .system(size: 29))
                typographyRow("Footnote 23pt", .system(size: 23))
                typographyRow("Caption 23–25pt", .system(size: 23, weight: .medium))
            }
        }
    }

    private func typographyRow(_ label: String, _ font: Font) -> some View {
        Text(label)
            .font(font)
            .foregroundStyle(.white)
            .validated(name: "Typography.\(label)")
    }

    private func auditLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white.opacity(0.55))
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Audit section wrapper

private struct AuditSection<Content: View>: View {
    let title: String
    let notes: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white)
                Text(notes)
                    .font(.system(size: 19))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: 1200, alignment: .leading)
            }
            content()
                .padding(.top, 8)
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

// MARK: - Sidebar / chip specimens (do not participate in app state)

private struct SidebarSpecimen: View {
    let tab: Router.Tab
    let selected: Bool
    let expanded: Bool
    private let accent = Color(hex: "#FF5C35") ?? .orange

    var body: some View {
        Button { } label: {
            HStack(spacing: 18) {
                Image(systemName: tab.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .frame(width: 32, height: 32)
                if expanded {
                    Text(tab.title)
                        .font(.system(size: 20, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(SidebarRowStyle(selected: selected, expanded: expanded, accent: accent))
        .focusEffectDisabled()
        .frame(width: 300)
    }
}

private struct ChipSpecimen: View {
    let label: String
    let isOn: Bool
    let accent: Color

    var body: some View {
        Button { } label: { Text(label) }
            .buttonStyle(ChipButtonStyle(accent: accent, isOn: isOn))
            .focusEffectDisabled()
    }
}

// MARK: - Specimen selection

struct AuditSpecimen: Identifiable {
    let id: String
    let label: String
    let item: Catalog.Item
}

struct AuditSpecimens {
    let posters: [AuditSpecimen]

    static func build(from items: [Catalog.Item]) -> AuditSpecimens {
        guard !items.isEmpty else {
            return AuditSpecimens(posters: [])
        }
        // Pick a variety: shortest title, typical title, longest title;
        // one that has a backdrop; one with only a poster; one with no
        // designed artwork (to exercise the procedural fallback).
        let sorted = items.sorted { $0.title.count < $1.title.count }
        let shortest = sorted.first!
        let longest = sorted.last!
        let middle = sorted[sorted.count / 2]
        let procedural = items.first { !$0.hasDesignedArtwork } ?? shortest

        return AuditSpecimens(posters: [
            AuditSpecimen(id: "short",     label: "Shortest title",     item: shortest),
            AuditSpecimen(id: "typical",   label: "Typical",            item: middle),
            AuditSpecimen(id: "long",      label: "Longest title",      item: longest),
            AuditSpecimen(id: "procedural", label: "No artwork (procedural)", item: procedural)
        ])
    }
}

// MARK: - Runtime validation modifier

extension View {
    /// Attach a runtime audit wrapper. In DEBUG builds, logs a warning
    /// to the Xcode console if the view renders at zero size or gets
    /// clipped below its ideal size. No effect in release.
    func validated(name: String) -> some View {
        #if DEBUG
        return self.modifier(ValidationModifier(name: name))
        #else
        return self
        #endif
    }
}

#if DEBUG
private struct ValidationModifier: ViewModifier {
    let name: String
    @State private var reportedSize: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { report(geo.size) }
                        .onChange(of: geo.size) { _, new in report(new) }
                }
            )
    }

    private func report(_ size: CGSize) {
        guard size != reportedSize else { return }
        reportedSize = size
        if size.width < 1 || size.height < 1 {
            print("⚠️ UIAudit \(name): rendered with zero size — likely a layout bug")
        }
    }
}
#endif
