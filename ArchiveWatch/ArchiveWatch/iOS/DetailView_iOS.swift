#if os(iOS)
import SwiftUI
import SwiftData

// Detail: full-bleed backdrop, metadata, Play, Favorite, synopsis, cast, and
// "More Like This". Native iOS: a scroll view with a prominent Play button and a
// fullScreenCover player; favorite is a toolbar/heart toggle backed by SwiftData.
struct DetailView: View {
    let item: Catalog.Item
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var ctx
    // IPAD-DESIGN §1.2: adaptivity by SIZE CLASS, never by device — so an
    // iPhone in landscape, an iPad in Split View and a Mac window are all
    // correct without a device check (§6.3 forbids one).
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
    @Query private var favorites: [Favorite]
    @State private var playing = false
    @State private var sceneStart: TimeInterval?
    @State private var scenes: [ArchiveVersions.Scene] = []
    @State private var startingSharePlay = false
    @State private var goingLive = false
    @State private var liveRequest: GoLiveRequest?
    @State private var isWatchedState = false
    @State private var versions: [ArchiveVersions.Version] = []
    @State private var loadingVersions = false
    @State private var chosenVersionName: String?
    /// §3.5b: a long synopsis opens at four lines, with More.
    @State private var synopsisExpanded = false
    @State private var synopsisShown: CGFloat = 0
    @State private var synopsisFull: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The action tiles grow with the text they carry.
    @ScaledMetric(relativeTo: .caption) private var tileHeight: CGFloat = 60
    @State private var addingToPlaylist = false
    @State private var clipping = false
    @State private var gettingSubtitles = false
    @State private var downloading = false
    @State private var casting = false
    @Query private var downloads: [DownloadedFilm]
    @State private var captionPlaybackChoice: CaptionPlaybackChoice?
    @State private var playbackError: String?

    private var isFav: Bool { favorites.contains { $0.archiveID == item.archiveID } }

    /// One glyph carrying the whole download state, so the row does not grow a
    /// second control for a feature that is off most of the time.
    private func downloadIcon(_ d: DownloadedFilm?) -> String {
        switch d?.state {
        case .completed:            return "arrow.down.circle.fill"
        case .queued, .downloading: return "arrow.down.circle.dotted"
        case .paused:               return "pause.circle"
        case .failed:               return "exclamationmark.circle"
        case nil:                   return "arrow.down.circle"
        }
    }

    private func downloadLabel(_ d: DownloadedFilm?) -> String {
        switch d?.state {
        case .completed:            return "Downloaded — manage"
        case .queued, .downloading: return "Downloading"
        case .paused:               return "Download paused"
        case .failed:               return "Download failed"
        case nil:                   return "Download to watch offline"
        }
    }

    /// The Detail action row (iOS-DESIGN §3.5b): four labeled buttons of
    /// equal width — Favorite, Download, Watch Together, More — and every
    /// other verb inside More. It was up to nine unlabeled icons in a row that
    /// scrolled off a 390pt screen (measured on the iPhone 12), so a viewer
    /// could neither read nor reach most of them.
    @ViewBuilder private var actionButtons: some View {
        // Four across at every text size a phone row can hold; at the
        // accessibility sizes the words truncated ("Downl…"), so two by two.
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8),
                                 count: dynamicTypeSize.isAccessibilitySize ? 2 : 4),
                  spacing: 8) {
            actionTile(isFav ? "Saved" : "Favorite", isFav ? "heart.fill" : "heart") {
                toggleFavorite()
            }
            .accessibilityLabel(isFav ? "Remove from favorites" : "Add to favorites")

            if item.videoURLParsed != nil {
                let download = downloads.first { $0.archiveID == item.archiveID }
                actionTile(downloadWord(download), downloadIcon(download),
                           tint: download?.state == .completed ? .green : nil) {
                    downloading = true
                }
                .accessibilityLabel(downloadLabel(download))
            }

            // WATCH TOGETHER, ONE TAP FROM THE FILM (§3.5a): a way to WATCH
            // this film, so it stays on the row rather than inside More.
            Menu {
                // SharePlay starts on the phone, where the FaceTime call is.
                Button {
                    Task {
                        switch await WatchTogether.shared.share(
                            archiveID: item.archiveID, title: item.title, year: item.year) {
                        case .started: playing = true
                        case .needsCall: startingSharePlay = true
                        case .cancelled: break
                        }
                    }
                } label: { Label("With friends…", systemImage: "shareplay") }
                // Always offered; the sheet explains a film it cannot air (§8.8).
                Button { goingLive = true } label: {
                    Label("With the world…", systemImage: "dot.radiowaves.left.and.right")
                }
            } label: {
                tileLabel("Together", "person.2.wave.2")
            }
            .accessibilityLabel("Watch Together")

            Menu {
                Button { addingToPlaylist = true } label: {
                    Label("Add to Playlist", systemImage: "text.badge.plus")
                }
                // Watched is a badge on tiles; this is where the viewer
                // corrects it (tvOS parity).
                Button { toggleWatched() } label: {
                    Label(isWatchedState ? "Mark as Not Watched" : "Mark as Watched",
                          systemImage: isWatchedState ? "checkmark.circle.fill" : "checkmark.circle")
                }
                if item.videoURLParsed != nil {
                    Button { gettingSubtitles = true } label: {
                        Label("Subtitles", systemImage: "captions.bubble")
                    }
                }
                // Decision 033: shown only for clippable (rights-cleared) titles.
                if item.isClippable {
                    Button { clipping = true } label: {
                        Label("Create a Clip", systemImage: "scissors")
                    }
                }
                // Which copy plays (owner, 2026-08-17): a phone on cellular
                // has every reason to want a lighter transfer.
                if item.videoURLParsed != nil {
                    Menu {
                        if StudioRoomCopy.isActive(for: item.archiveID) {
                            Text("In a Watch Together room, the host chooses the copy.")
                        } else if versions.isEmpty {
                            Text(loadingVersions ? "Loading…" : "No other copies")
                        } else {
                            ForEach(versions) { v in
                                Button {
                                    ArchiveVersions.choose(v, for: item.archiveID)
                                    chosenVersionName = v.choiceKey
                                } label: {
                                    Label(v.label, systemImage:
                                        chosenVersionName == v.choiceKey ? "checkmark.circle.fill" : "circle")
                                }
                            }
                            Button(role: .destructive) {
                                ArchiveVersions.choose(nil, for: item.archiveID)
                                chosenVersionName = nil
                            } label: { Label("Use the default copy", systemImage: "arrow.uturn.backward") }
                        }
                    } label: {
                        Label(chosenVersionName == nil ? "Choose a Copy" : "Choose a Copy (chosen)",
                              systemImage: "rectangle.stack")
                    }
                }
                // A film in its own window (IPAD-DESIGN §9.1); never on iPhone.
                if supportsMultipleWindows {
                    Button { openWindow(id: FilmWindow.id, value: item.archiveID) } label: {
                        Label("Open in New Window", systemImage: "macwindow.badge.plus")
                    }
                }
                Divider()
                ShareLink(item: shareURL) {
                    Label("Share Link…", systemImage: "square.and.arrow.up")
                }
                if Callsheet.supports(item) {
                    Button { Callsheet.open(Callsheet.url(for: item)) } label: {
                        Label(Callsheet.actionTitle, systemImage: Callsheet.actionIcon)
                    }
                }
                // Cast to a TV (§8.10): most iPhone owners reach a TV by
                // AirPlay, which the player already offers.
                if item.videoURLParsed != nil {
                    Button { casting = true } label: {
                        let cast = CastController.shared
                        Label(cast.archiveID == item.archiveID && cast.phase == .casting
                              ? "Casting to \(cast.deviceName)…" : "Cast to a TV…",
                              systemImage: "tv")
                    }
                }
                Link(destination: archiveOrgURL) {
                    Label("View on archive.org", systemImage: "globe")
                }
                if let report = FilmProblem.url(archiveID: item.archiveID) {
                    Link(destination: report) {
                        Label("Something wrong with this film?", systemImage: "exclamationmark.bubble")
                    }
                }
            } label: {
                tileLabel("More", "ellipsis")
            }
            .accessibilityLabel("More actions")
        }
        .task(id: item.archiveID) {
            chosenVersionName = ArchiveVersions.chosenName(for: item.archiveID)
            guard item.videoURLParsed != nil, versions.isEmpty else { return }
            loadingVersions = true
            versions = await ArchiveVersions.list(itemID: item.archiveID)
            loadingVersions = false
        }
    }

    private func downloadWord(_ d: DownloadedFilm?) -> String {
        switch d?.state {
        case .completed?: "Downloaded"
        case .queued?, .downloading?: "Downloading"
        case .paused?: "Paused"
        case .failed?: "Retry"
        case nil: "Download"
        }
    }

    /// An icon over a word, filling an equal share of the row.
    private func tileLabel(_ word: String, _ icon: String, tint: Color? = nil) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.title3).frame(minHeight: 24)
            Text(word).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(tint ?? .primary)
        // A fixed height: the four symbols differ in height, and a menu label
        // and a button label size themselves differently.
        .frame(maxWidth: .infinity)
        .frame(height: tileHeight)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
        .contentShape(.rect)
    }

    private func actionTile(_ word: String, _ icon: String, tint: Color? = nil,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) { tileLabel(word, icon, tint: tint) }
            .buttonStyle(.plain)
    }

    /// Title, meta, the primary action and the action row — the column that
    /// sits beside the artwork at regular width (IPAD-DESIGN §3.1).
    @ViewBuilder private var identityBlock: some View {
                Text(item.title).font(.title.bold())
                // "Also known as" (Decision 100). The catalog has always
                // carried the film's primary title; showing it turns a
                // description that looked mismatched into the fact that one
                // film circulated under several names.
                if let aka = item.alsoKnownAs {
                    Text("Also known as \(aka)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(metaLine).font(.subheadline).foregroundStyle(.secondary)

                // Play gets its OWN row. It used to share one HStack with the
                // icon buttons, so each icon added stole width from it — and
                // once the subtitles button made five, "Play · 28 min" was
                // squeezed to one character per line. A row whose layout
                // degrades as actions are added is a row that will break
                // again, so the fix is structural rather than a tighter font.
                Button { playing = true } label: {
                    Label(playLabel, systemImage: "play.fill")
                        .lineLimit(1)              // never wrap, whatever happens
                        // IPAD-DESIGN §2.2: capped at 480pt on regular width.
                        // A control's width is a claim about its importance
                        // (§1.4), and this one measured 1040pt across a
                        // 12.9-inch screen.
                        .frame(maxWidth: hSize == .regular ? 480 : .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Brand.primary)
                .controlSize(.large)
                .disabled(item.videoURLParsed == nil)

                // Four equal tiles cannot overflow (§3.5b). Before them, nine
                // bordered icons overflowed a 390pt phone and needed a
                // horizontal ScrollView; an overflowing HStack also widens the
                // whole column (the "-lis" defect of 2026-08-28).
                actionButtons
                    .frame(maxWidth: hSize == .regular ? 480 : .infinity)

    }

    /// Prose and facts. Width-capped at regular width by the caller (§2.1).
    @ViewBuilder private var proseBlock: some View {
                if let tagline = item.tagline, !tagline.isEmpty {
                    Text(tagline).font(.callout).italic().foregroundStyle(.secondary)
                }
                if let s = item.displaySynopsis {
                    // Four lines, then More (§3.5b): the synopsis is the part
                    // everyone reads the start of and few read to the end, and
                    // at full length it pushed the cast off the first screen.
                    // Measured, not a character count: at the iPad's 700pt a
                    // 240-character synopsis fits in four lines, and "More"
                    // then offered nothing.
                    Text(s).font(.body).foregroundStyle(.primary.opacity(0.9))
                        .lineLimit(synopsisExpanded ? nil : 4)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { synopsisShown = $0 }
                        .background(alignment: .topLeading) {
                            Text(s).font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                                .hidden()
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { synopsisFull = $0 }
                        }
                    if synopsisExpanded || synopsisFull > synopsisShown + 1 {
                        Button(synopsisExpanded ? "Less" : "More") {
                            withAnimation(.easeInOut(duration: 0.2)) { synopsisExpanded.toggle() }
                        }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.borderless)
                    }
                    if let prov = item.synopsisProvenance {
                        Text(prov).font(.caption).foregroundStyle(.secondary)
                    }
                }
                // The facts are short label/value pairs, so at regular width
                // they ride the trailing column BESIDE the artwork (where an
                // iPad reader expects a metadata panel). Compact folds them
                // into one Details disclosure (§3.5b): studio, writer, music
                // and cinematography are wanted by some readers, not first.
                if hSize != .regular, DetailFacts.hasFacts(item) {
                    DisclosureGroup("Details") {
                        DetailFacts(item: item).padding(.top, 6)
                    }
                    .font(.subheadline.weight(.semibold))
                }
                // Episode item (Decision 045): a way back to the full series.
                if item.isEpisode, let sid = item.seriesID {
                    Button {
                        if let card = store.seriesCard(seriesID: sid) { router.push(SeriesRef(card: card)) }
                    } label: {
                        Label("Part of \(item.seriesTitle ?? "the series")", systemImage: "tv")
                    }
                    .buttonStyle(.bordered)
                }
    }

    /// Cast, community and More Like This — full width, horizontally
    /// scrolling, more members visible on a wider screen (§3.3).
    @ViewBuilder private var rowsBlock: some View {
                if !item.cast.isEmpty || item.director?.isEmpty == false {
                    CastRow(cast: item.cast, director: item.director,
                            directorProfilePath: item.directorProfilePath)
                }
                // A viewer review is PROSE, so §2.1's measure cap applies to
                // it exactly as it does to the synopsis — reviews ran 976pt on
                // a 13-inch screen, which the synopsis cap alone never touched
                // because they live here rather than in proseBlock.
                CommunityDetailSection(item: item)
                    .frame(maxWidth: hSize == .regular ? 700 : .infinity,
                           alignment: .leading)
                scenesSection
                relatedSection
    }

    @ViewBuilder private var stackedHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            DetailHero(poster: Self.upsized(item.posterURLParsed),
                       backdrop: Self.upsized(item.backdropURLParsed))
            VStack(alignment: .leading, spacing: 12) { identityBlock }
                .padding(.horizontal)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // IPAD-DESIGN §3.1: two columns at regular width — artwork
                // leading, identity and actions beside it — and one stacked
                // column when compact. One view, a size-class branch inside
                // it (§6.2 forbids a second Detail).
                if hSize == .regular {
                    // Two columns only when the identity column keeps 360pt:
                    // regular width alone is not enough — Stage Manager or an
                    // 11-inch in portrait squeezed Play to ~150-350pt (§5.2).
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 28) {
                            DetailHero(poster: Self.upsized(item.posterURLParsed),
                                       backdrop: Self.upsized(item.backdropURLParsed))
                                .frame(width: 460)
                            VStack(alignment: .leading, spacing: 12) {
                                identityBlock
                                DetailFacts(item: item)
                                    .padding(.top, 4)
                            }
                            .frame(minWidth: 360, maxWidth: 520, alignment: .leading)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal)
                        stackedHero
                    }
                } else {
                    stackedHero
                }

                VStack(alignment: .leading, spacing: 12) { proseBlock }
                    // §2.1: prose is capped at 700pt so a 1366pt screen cannot
                    // stretch body copy to 115 characters a line (measured).
                    .frame(maxWidth: hSize == .regular ? 700 : .infinity,
                           alignment: .leading)
                    .padding(.horizontal)

                // §3.3: the horizontally scrolling rows keep the full width —
                // a wide screen means more faces visible, not bigger ones.
                VStack(alignment: .leading, spacing: 16) { rowsBlock }
                    .padding(.horizontal)
            }
        }
        .titleInContent(item.title)
        .sheet(isPresented: $startingSharePlay) {
            SharePlayStarter(
                activity: WatchTogether.shared.activity(archiveID: item.archiveID,
                                                        title: item.title,
                                                        year: item.year)
            ) { started in
                startingSharePlay = false
                if started { playing = true }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $goingLive) {
            GoLiveSheet(film: item) { req in
                liveRequest = req
            }
        }
        // The Studio is the PLAYER in a production mode, so it is the same
        // §3.7 cover the player uses — bound to an ITEM, never a Bool
        // (§4.4's rule, and the black-player race it came from).
        .fullScreenCover(item: $liveRequest) { req in
            StudioPlayerContainer(item: item, request: req) {
                liveRequest = nil
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $playing, onDismiss: { sceneStart = nil }) {
            PlayerView(item: item, autoplayIn: store, onUnplayable: { message in
                playing = false
                playbackError = message
            }, captionChoice: captionPlaybackChoice, startAt: sceneStart).ignoresSafeArea()
            // A room guest's one line (SHAREPLAY §11.6.1).
            .overlay(alignment: .top) {
                StudioRoomNotice().padding(.top, 12)
            }
        }
        .alert("Can't play this title", isPresented: .constant(playbackError != nil)) {
            Button("OK") { playbackError = nil }
        } message: {
            Text(playbackError ?? "")
        }
        .focusedSceneValue(\.filmMenuActions, menuActions)
        .sheet(isPresented: $addingToPlaylist) {
            AddToPlaylistSheet(archiveID: item.archiveID)
        }
        .sheet(isPresented: $clipping) {
            ClipStudioView(source: item.clipSource)
        }
        .sheet(isPresented: $gettingSubtitles) {
            GetSubtitlesView(item: item, playbackChoice: $captionPlaybackChoice)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $downloading) {
            DownloadSheet(item: item)
        }
        .sheet(isPresented: $casting) {
            CastSheet(item: item)
                .presentationDetents([.medium, .large])
        }
        // Dev affordance (with AW_START_ITEM): start playback immediately so
        // playback diagnostics can run unattended on the simulator.
        .task(id: item.archiveID) {
            isWatchedState = store.completedArchiveIDs.contains(item.archiveID)
                || WatchProgress.isWatched(archiveID: item.archiveID, in: ctx)
        }
        .task {
            // Joining a SharePlay session must actually START the film, not just
            // land on its Detail page: the group coordinates a PLAYER, so a
            // joiner sitting on Detail stays black while everyone else watches
            // (owner, 2026-09-01: "it opened the app, but I don't see the video
            // playing"). RootView routes us here; this is the half that plays.
            if WatchTogether.shared.pendingJoin == item.archiveID,
               item.videoURLParsed != nil {
                WatchTogether.shared.consumePendingJoin()
                playing = true
            }
            // JOINING A ROOM STARTS THE FILM, the same as joining SharePlay
            // above. The code waits for the player (it is where the AVPlayer
            // exists) and nothing opened one, so a guest who typed the code
            // landed on Detail and nothing happened. Owner, 2026-09-25: "it
            // isn't working to launch into the Watch Together experience."
            if let code = RoomJoin_iOS.shared.pending,
               RoomJoin_iOS.shared.pendingFilm == item.archiveID,
               item.videoURLParsed != nil {
                // A ROOM LINK names the film but not the host's copy, so the
                // room is read first: the player built next must play the
                // host's file (StudioRoomCopy), never this device's choice.
                if !StudioRoomCopy.isActive(for: item.archiveID) {
                    _ = await StudioRoomCopy.prime(code: code)
                }
                playing = true
            }
            if ProcessInfo.processInfo.environment["AW_AUTOPLAY"] == "1",
               item.videoURLParsed != nil {
                // The go-live door presents the STUDIO cover — the same one the
                // sheet presents — and the plain player otherwise. iOS had no
                // unattended way into the Studio at all, which is why the
                // "prove it end to end on the iPhone" item kept coming back.
                if let req = StudioDoors.goLiveRequest(film: item) {
                    liveRequest = req
                } else {
                    // After the screen settles: a cover requested during the
                    // first task can be dropped by the presentation machinery.
                    try? await Task.sleep(for: .seconds(1.5))
                    playing = true
                }
            }
            // Screen-audit hook (caption loop W6): present the subtitles sheet
            // deterministically — simctl cannot tap, and a sheet nobody can
            // open unattended is a sheet nobody can regression-test. No-op in
            // production like every AW_ hook.
            if ProcessInfo.processInfo.environment["AW_SHOW_SUBTITLES"] == "1" {
                gettingSubtitles = true
            }
            #if DEBUG
            if ProcessInfo.processInfo.environment["AW_CAST"] != nil { casting = true }
            #endif
        }
    }

    private var metaLine: String {
        [item.year.map(String.init), item.runtimeSeconds.map { "\($0/60) min" },
         ContentType.label(item.contentType),
         item.director.map { "Dir. \($0)" }].compactMap { $0 }.joined(separator: " · ")
    }
    /// "Resume · 34 min" once there is a position worth returning to, matching
    /// tvOS. It said "Play · 91 min" however far in you were, so a viewer
    /// forty minutes into a film could not tell whether the button would carry
    /// on or start over — while the player resumed regardless (iPhone 12
    /// audit, 2026-08-28).
    private var playLabel: String {
        if let remaining = WatchProgress.remainingSeconds(
            archiveID: item.archiveID, in: ctx) {
            return "Resume · \(remaining / 60) min"
        }
        return item.runtimeSeconds.map { "Play · \($0/60) min" } ?? "Play"
    }
    private var shareURL: URL {
        URL(string: "https://archivewatch.org/item/\(item.archiveID)")!
    }
    private var archiveOrgURL: URL {
        URL(string: "https://archive.org/details/\(item.archiveID)") ?? shareURL
    }

    /// Detail wants sharper art than shelf tiles: upgrade known CDN size tokens
    /// (TMDb /t/p/wNNN, OMDb/Amazon _SX300) to detail-appropriate sizes. URLs
    /// without a recognized token pass through untouched.
    static func upsized(_ url: URL?) -> URL? {
        guard let s = url?.absoluteString else { return nil }
        var out = s
        for small in ["/t/p/w185/", "/t/p/w342/", "/t/p/w500/"] {
            out = out.replacingOccurrences(of: small, with: "/t/p/w780/")
        }
        out = out.replacingOccurrences(of: "_SX300", with: "_SX800")
        return URL(string: out) ?? url
    }

    private func toggleWatched() {
        if WatchProgress.setWatched(!isWatchedState, in: ctx, archiveID: item.archiveID) {
            isWatchedState.toggle()
        }
        SyncNudge.nudge(ctx)
        if isWatchedState { store.completedArchiveIDs.insert(item.archiveID) }
        else { store.completedArchiveIDs.remove(item.archiveID) }
    }

    /// What the menu bar's Film menu acts on (IPAD-DESIGN §8.2).
    private var menuActions: FilmMenuActions {
        FilmMenuActions(
            title: item.title, isFavorite: isFav, isWatched: isWatchedState,
            canPlay: item.videoURLParsed != nil,
            play: { playing = true },
            toggleFavorite: { toggleFavorite() },
            addToPlaylist: { addingToPlaylist = true },
            toggleWatched: { toggleWatched() },
            openInNewWindow: supportsMultipleWindows
                ? { openWindow(id: FilmWindow.id, value: item.archiveID) } : nil,
            pageURL: shareURL, archiveURL: archiveOrgURL,
            reportURL: FilmProblem.url(archiveID: item.archiveID))
    }

    private func toggleFavorite() {
        if let f = favorites.first(where: { $0.archiveID == item.archiveID }) {
            ctx.delete(f)
            SyncNudge.recordDeletion("fav:\(item.archiveID)", in: ctx)
        } else {
            ctx.insert(Favorite(archiveID: item.archiveID)); try? ctx.save()
            SyncNudge.nudge(ctx)
        }
    }

    /// Scenes (iOS-DESIGN §5.2c): a frame plays the film from its second.
    @ViewBuilder private var scenesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !scenes.isEmpty {
                Text("Scenes").font(.title3).fontWeight(.semibold)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 14) {
                        ForEach(scenes, id: \.seconds) { s in
                            Button {
                                sceneStart = TimeInterval(s.seconds)
                                playing = true
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    AsyncImage(url: s.image) { $0.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.2) }
                                        .frame(width: 160, height: 120)
                                        .clipShape(.rect(cornerRadius: 10))
                                    Text(Self.clock(s.seconds)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Play from \(Self.clock(s.seconds))")
                        }
                    }
                }.scrollIndicators(.hidden)
            }
        }
        .task(id: item.archiveID) {
            guard let url = item.videoURLParsed else { scenes = []; return }
            scenes = await ArchiveVersions.scenes(for: item.archiveID, default: url)
        }
    }

    private static func clock(_ t: Int) -> String {
        t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60)
                  : String(format: "%d:%02d", t / 60, t % 60)
    }

    @ViewBuilder private var relatedSection: some View {
        let related = store.related(to: item)
        if !related.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("More Like This").font(.title3).fontWeight(.semibold)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 14) {
                        ForEach(related) { r in
                            Button { router.openDetail(r) } label: { PosterTile(item: r, width: 100) }
                                .buttonStyle(.plain)
                        }
                    }
                }.scrollIndicators(.hidden)
            }
        }
    }
}

// Detail header artwork: the POSTER, aspect-fit and explicitly height-framed so
// it can never render fill-cropped (owner report 2026-06-10: posters were
// cropped/low-res on the title view), floating over a blurred ambient fill of
// the backdrop (or the poster itself). Taller on iPad/regular width.
private struct DetailHero: View {
    let poster: URL?
    let backdrop: URL?
    @Environment(\.horizontalSizeClass) private var hSize

    private var height: CGFloat { hSize == .regular ? 460 : 340 }

    var body: some View {
        PosterImage(url: poster ?? backdrop, contentMode: .fit)
            .frame(height: height - 32)
            .clipShape(.rect(cornerRadius: 12))
            .shadow(color: .black.opacity(0.5), radius: 14, y: 6)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            // Ambient fill MUST be a .background: a fill-mode image reports its
            // COVER size (not the proposal) and frame(maxWidth:.infinity) adopts
            // an oversized child — a 16:9 backdrop covering this 340pt hero
            // reported 604pt wide and dragged the whole Detail column off both
            // screen edges (owner screenshot 2026-06-10; poster-only items were
            // unaffected, which is why it was intermittent). A background can
            // never influence layout; the overflow just gets clipped.
            .background {
                PosterImage(url: backdrop ?? poster)
                    .blur(radius: 28)
                    .overlay(Color.black.opacity(0.45))
            }
            .clipped()
    }
}

// Tappable cast & crew (#4 parity with tvOS PersonChip): each bubble pushes a
// browse of that person's other titles via the FTS names index. Director leads.
private struct CastRow: View {
    let cast: [Catalog.CastMember]
    var director: String? = nil
    var directorProfilePath: String? = nil
    @Environment(Router.self) private var router

    /// TMDb profile paths are stored as "/abc.jpg"; full URLs pass through.
    static func profileURL(_ path: String?) -> URL? {
        guard let p = path, !p.isEmpty else { return nil }
        if p.hasPrefix("http") { return URL(string: p) }
        return URL(string: "https://image.tmdb.org/t/p/w185\(p)")
    }

    /// Up-to-two-letter initials for a photoless avatar (e.g. the director).
    static func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cast & Crew").font(.title3).fontWeight(.semibold)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 16) {
                    if let d = director, !d.isEmpty {
                        bubble(name: d, role: "Director", profilePath: directorProfilePath, personID: nil)
                    }
                    ForEach(cast.prefix(12), id: \.name) { member in
                        bubble(name: member.name, role: member.character,
                               profilePath: member.profilePath, personID: member.tmdbPersonID)
                    }
                }
            }.scrollIndicators(.hidden)
        }
    }

    private func bubble(name: String, role: String?, profilePath: String?, personID: Int?) -> some View {
        Button {
            router.push(BrowseFilterRoute(title: name, person: name))
        } label: {
            VStack(spacing: 4) {
                Group {
                    // A photoless member (e.g. the director — stored name-only, no profile path)
                    // degrades to an initials circle, not PosterImage's "film" glyph which reads
                    // as a broken image (owner 2026-06-29).
                    if let url = Self.profileURL(profilePath) {
                        PosterImage(url: url)
                    } else {
                        Circle().fill(.quaternary)
                            .overlay(Text(Self.initials(name)).font(.headline).foregroundStyle(.secondary))
                    }
                }
                .frame(width: 64, height: 64).clipShape(.circle)
                .overlay(Circle().strokeBorder(.white.opacity(0.1)))
                Text(name).font(.caption2).lineLimit(2)
                    .frame(width: 72).multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                if let role, !role.isEmpty {
                    Text(role).font(.system(size: 9)).foregroundStyle(.secondary)
                        .lineLimit(1).frame(width: 72)
                }
            }
        }
        .buttonStyle(.plain)
        // Long-press → open this person directly in Callsheet (Decision 046
        // unblocks the person deep-link via tmdbPersonID; the primary tap still
        // browses their other titles).
        .contextMenu {
            if let pid = personID, Callsheet.isInstalled,
               let url = Callsheet.personURL(tmdbPersonID: pid) {
                Button { Callsheet.open(url) } label: {
                    Label("Open in Callsheet", systemImage: "person.text.rectangle")
                }
            }
        }
    }
}

// Tier 1+2 metadata-expansion facts (Decision 046): franchise, studios, full
// crew, awards. Each row only renders when the field is present, so unmatched
// films show nothing extra.
private struct DetailFacts: View {
    let item: Catalog.Item

    var body: some View {
        let rows = facts
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(rows, id: \.0) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(row.0).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                        Text(row.1).font(.caption).foregroundStyle(.primary.opacity(0.85))
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    /// Whether there is anything to disclose — a Details row over nothing
    /// is a promise the page cannot keep.
    static func hasFacts(_ item: Catalog.Item) -> Bool { !DetailFacts(item: item).facts.isEmpty }

    fileprivate var facts: [(String, String)] {
        var out: [(String, String)] = []
        if let f = item.franchise, !f.isEmpty { out.append(("Part of", f)) }
        if !item.studios.isEmpty { out.append(("Studio", item.studios.joined(separator: ", "))) }
        if let w = item.writer, !w.isEmpty { out.append(("Writer", w)) }
        if let c = item.composer, !c.isEmpty { out.append(("Music", c)) }
        if let dp = item.cinematographer, !dp.isEmpty { out.append(("Cinematography", dp)) }
        if let a = item.awards, !a.isEmpty { out.append(("Awards", a)) }
        return out
    }
}

#endif
