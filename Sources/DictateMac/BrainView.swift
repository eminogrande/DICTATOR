import DictateMacCore
import SwiftUI

struct BrainView: View {
    @StateObject private var controller: BrainController
    @State private var showsTextImporter = false
    @State private var importTitle = ""
    @State private var importText = ""

    init(controller: BrainController) {
        _controller = StateObject(wrappedValue: controller)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            repositoryBar
            Divider()
            HSplitView {
                sidebar
                    .frame(minWidth: 180, idealWidth: 210, maxWidth: 240)
                content
                    .frame(minWidth: 360, idealWidth: 430)
                detail
                    .frame(minWidth: 420)
            }
        }
        .font(.system(size: 17))
        .frame(minWidth: 1_080, minHeight: 700)
        .task { controller.refresh() }
        .onExitCommand { controller.goHome() }
        .sheet(isPresented: $showsTextImporter) { textImporter }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button {
                controller.goHome()
            } label: {
                Label("Home", systemImage: "chevron.left")
            }
            .disabled(controller.section == .home)
            .help("Return to Brain Home (Esc)")

            TextField("Search meetings, preferences, code…", text: $controller.query)
                .textFieldStyle(.roundedBorder)
                .onSubmit { controller.search() }

            Button("Search") { controller.search() }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(controller.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || controller.isBusy)

            if controller.section == .search {
                Button("Clear") { controller.clearSearch() }
            }

            Spacer()
            if let stats = controller.stats {
                Text("\(stats.nodes) nodes · \(stats.edges) connections")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    private var repositoryBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "shippingbox")
                    .foregroundStyle(.secondary)
                TextField("https://github.com/owner/repository or local path", text: $controller.repositoryURL)
                    .textFieldStyle(.roundedBorder)
                Button("Import Repository") { controller.importRepository() }
                    .disabled(controller.repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || controller.isBusy)
            }
            HStack(spacing: 10) {
                Button("Add Text", systemImage: "text.badge.plus") { showsTextImporter = true }
                Button("Import Export or Files", systemImage: "square.and.arrow.down") { controller.importFiles() }
                Button("Sync Hermes Memory", systemImage: "brain") { controller.syncHermesMemory() }
                Spacer()
            }
        }
        .padding(12)
    }

    private var textImporter: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add context to Brain")
                .font(.system(size: 22, weight: .semibold))
            TextField("Useful title", text: $importTitle)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 17))
            TextEditor(text: $importText)
                .font(.system(size: 17))
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
            HStack {
                Spacer()
                Button("Cancel") { showsTextImporter = false }
                Button("Add to Brain") {
                    controller.importText(label: importTitle, text: importText)
                    importTitle = ""
                    importText = ""
                    showsTextImporter = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(importTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .font(.system(size: 17))
        .padding(24)
        .frame(width: 640, height: 480)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("BROWSE")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 4)

            ForEach(BrainBrowserSection.sidebarSections) { section in
                Button {
                    controller.selectSection(section)
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: section.systemImage)
                            .frame(width: 18)
                        Text(section.title)
                        Spacer()
                        if let count = count(for: section) {
                            Text("\(count)")
                                .font(.system(size: 17).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(controller.section == section ? Color.accentColor.opacity(0.2) : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 4)
            }

            Spacer()
            Divider()
            HStack(spacing: 7) {
                if controller.isBusy { ProgressView().controlSize(.small) }
                Text(controller.status)
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            .padding(12)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(controller.section.title)
                    .font(.title2.weight(.semibold))
                Text(controller.section == .home ? "Overview and recent recordings" : "\(controller.results.count) items")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
            }
            .padding(14)

            Divider()

            if controller.section == .home {
                homeContent
            } else {
                resultList
            }
        }
    }

    private var homeContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let stats = controller.stats {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        statCard("Recordings", value: stats.nodeTypes["recording"] ?? 0, icon: "waveform")
                        statCard("Agent Sessions", value: stats.nodeTypes["session"] ?? 0, icon: "bubble.left.and.bubble.right")
                        statCard("Memories", value: stats.nodeTypes["memory"] ?? 0, icon: "brain")
                        statCard("Repositories", value: stats.nodeTypes["project"] ?? 0, icon: "shippingbox")
                    }
                }

                Text("Recent recordings")
                    .font(.system(size: 17, weight: .semibold))

                if controller.results.isEmpty && !controller.isBusy {
                    emptyState("No recordings yet", icon: "waveform")
                } else {
                    ForEach(controller.results) { resultRow($0) }
                }
            }
            .padding(14)
        }
    }

    private var resultList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                if controller.results.isEmpty && !controller.isBusy {
                    emptyState(controller.section == .search ? "No matching evidence" : "No sources in this section", icon: controller.section.systemImage)
                } else {
                    ForEach(controller.results) { resultRow($0) }
                }
            }
            .padding(10)
        }
    }

    private func resultRow(_ item: BrainSearchItem) -> some View {
        Button {
            controller.select(item)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Image(systemName: icon(for: item.type))
                        .foregroundStyle(color(for: item.type))
                    Text(item.label)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(item.type.uppercased())
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Text(item.excerpt)
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                if let path = item.path {
                    Text(path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                        .font(.system(size: 17).monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(controller.selectedItem?.id == item.id ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor).opacity(0.55))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var detail: some View {
        if let item = controller.selectedItem {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        Image(systemName: icon(for: item.type))
                            .font(.title2)
                            .foregroundStyle(color(for: item.type))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.label)
                                .font(.title2.weight(.semibold))
                            Text(item.type.uppercased())
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if item.path != nil {
                            Button("Open Source") { controller.openSelected() }
                        }
                    }

                    if let path = item.path {
                        Text(path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                            .font(.system(size: 17).monospaced())
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                    }

                    Text(item.excerpt)
                        .font(.system(size: 17))
                        .textSelection(.enabled)

                    Divider()
                    Text("Connected evidence")
                        .font(.system(size: 17, weight: .semibold))
                    BrainMap(items: [item])
                        .frame(height: 330)

                    if !item.related.isEmpty {
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(item.related) { related in
                                HStack(spacing: 8) {
                                    Circle().fill(color(for: related.type)).frame(width: 7, height: 7)
                                    Text(related.label).lineLimit(1)
                                    Spacer()
                                    Text(related.type).font(.system(size: 17)).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } else {
                        Text("No direct connections indexed for this source.")
                            .font(.system(size: 17))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(18)
            }
        } else {
            ContentUnavailableView(
                "Select a source",
                systemImage: "point.3.connected.trianglepath.dotted",
                description: Text("Choose a recording, transcript, repository, file, or search result to inspect its evidence and connections.")
            )
        }
    }

    private func statCard(_ title: String, value: Int, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon).foregroundStyle(.secondary)
            Text("\(value)").font(.title2.weight(.semibold).monospacedDigit())
            Text(title).font(.system(size: 17)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color(nsColor: .controlBackgroundColor).opacity(0.7)))
    }

    private func emptyState(_ title: String, icon: String) -> some View {
        ContentUnavailableView(title, systemImage: icon)
            .frame(maxWidth: .infinity, minHeight: 220)
    }

    private func count(for section: BrainBrowserSection) -> Int? {
        guard let stats = controller.stats else { return nil }
        switch section {
        case .home: return nil
        case .all: return stats.nodes - (stats.nodeTypes["keyword"] ?? 0)
        case .search: return nil
        default: return stats.nodeTypes[section.rawValue] ?? 0
        }
    }

    private func icon(for type: String) -> String {
        switch type {
        case "recording": "waveform"
        case "transcript": "text.quote"
        case "session": "bubble.left.and.bubble.right"
        case "turn": "bubble.left"
        case "memory": "brain"
        case "document": "doc.text"
        case "project": "shippingbox"
        case "file": "doc"
        case "function": "function"
        case "prompt": "text.bubble"
        default: "circle"
        }
    }

    private func color(for type: String) -> Color {
        switch type {
        case "recording": .orange
        case "transcript": .blue
        case "session", "turn": .indigo
        case "memory": .mint
        case "document": .cyan
        case "project": .purple
        case "file": .green
        case "function": .pink
        case "prompt": .teal
        default: .secondary
        }
    }
}

private struct BrainMap: View {
    let items: [BrainSearchItem]

    private struct VisualNode: Identifiable {
        let id: String
        let label: String
        let type: String
        let isRoot: Bool
    }

    private var nodes: [VisualNode] {
        var result: [VisualNode] = []
        var seen = Set<String>()
        for item in items.prefix(18) where seen.insert(item.id).inserted {
            result.append(.init(id: item.id, label: item.label, type: item.type, isRoot: true))
        }
        for related in items.flatMap(\.related).prefix(30) where seen.insert(related.id).inserted {
            result.append(.init(id: related.id, label: related.label, type: related.type, isRoot: false))
        }
        return Array(result.prefix(32))
    }

    private var edges: [(String, String)] {
        let visible = Set(nodes.map(\.id))
        return items.flatMap { item in
            item.related.compactMap { related in
                visible.contains(item.id) && visible.contains(related.id) ? (item.id, related.id) : nil
            }
        }
    }

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let positions = positions(in: size)
                for edge in edges {
                    guard let start = positions[edge.0], let end = positions[edge.1] else { continue }
                    var path = Path()
                    path.move(to: start)
                    path.addLine(to: end)
                    context.stroke(path, with: .color(.secondary.opacity(0.32)), lineWidth: 1)
                }
                for node in nodes {
                    guard let point = positions[node.id] else { continue }
                    let radius: CGFloat = node.isRoot ? 8 : 5
                    let circle = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
                    context.fill(circle, with: .color(color(node.type)))
                    let text = Text(node.label).font(.system(size: 17)).foregroundStyle(Color.primary)
                    context.draw(text, at: CGPoint(x: point.x, y: point.y + 15), anchor: .top)
                }
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor).opacity(0.55)))
        }
    }

    private func positions(in size: CGSize) -> [String: CGPoint] {
        guard !nodes.isEmpty else { return [:] }
        let center = CGPoint(x: size.width / 2, y: size.height / 2 - 8)
        var result: [String: CGPoint] = [:]
        let roots = nodes.filter(\.isRoot)
        let related = nodes.filter { !$0.isRoot }
        for (index, node) in roots.enumerated() {
            let angle = (Double(index) / Double(max(roots.count, 1))) * .pi * 2 - .pi / 2
            let radius = roots.count == 1 ? 0 : min(size.width, size.height) * 0.16
            result[node.id] = CGPoint(x: center.x + CGFloat(cos(angle)) * radius, y: center.y + CGFloat(sin(angle)) * radius)
        }
        for (index, node) in related.enumerated() {
            let angle = (Double(index) / Double(max(related.count, 1))) * .pi * 2 - .pi / 2
            let radius = min(size.width, size.height) * 0.36
            result[node.id] = CGPoint(x: center.x + CGFloat(cos(angle)) * radius, y: center.y + CGFloat(sin(angle)) * radius)
        }
        return result
    }

    private func color(_ type: String) -> Color {
        switch type {
        case "recording": .orange
        case "transcript": .blue
        case "session", "turn": .indigo
        case "memory": .mint
        case "document": .cyan
        case "project": .purple
        case "file": .green
        case "function": .pink
        case "prompt": .teal
        default: .gray
        }
    }
}
