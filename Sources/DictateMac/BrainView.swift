import DictateMacCore
import SwiftUI

struct BrainView: View {
    @ObservedObject var controller: BrainController

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                results
                    .frame(minWidth: 360)
                BrainMap(items: controller.results)
                    .frame(minWidth: 360)
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .onAppear { controller.refresh() }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                Text("DICTATOR Brain")
                    .font(.title2.bold())
                Spacer()
                if controller.isBusy { ProgressView().controlSize(.small) }
                Text(controller.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                TextField("Search meetings, preferences, code…", text: $controller.query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { controller.search() }
                Button("Search") { controller.search() }
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(controller.isBusy || controller.query.isEmpty)
            }
            HStack {
                TextField("https://github.com/owner/repository", text: $controller.repositoryURL)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { controller.importRepository() }
                Button("Import GitHub Repository") { controller.importRepository() }
                    .disabled(controller.isBusy || controller.repositoryURL.isEmpty)
            }
            if let stats = controller.stats {
                HStack(spacing: 18) {
                    Label("\(stats.nodes) nodes", systemImage: "circle.grid.cross")
                    Label("\(stats.edges) connections", systemImage: "point.3.connected.trianglepath.dotted")
                    ForEach(stats.nodeTypes.keys.sorted().prefix(4), id: \.self) { key in
                        Text("\(key): \(stats.nodeTypes[key] ?? 0)")
                    }
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    private var results: some View {
        Group {
            if controller.results.isEmpty {
                ContentUnavailableView("Search your Brain", systemImage: "brain", description: Text("Recordings refresh automatically. Import GitHub repositories above."))
            } else {
                List(controller.results) { item in
                    Button { controller.open(item) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(item.label).font(.headline).lineLimit(1)
                                Spacer()
                                Text(item.type.uppercased()).font(.caption2).foregroundStyle(.secondary)
                            }
                            Text(item.excerpt).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                            if !item.related.isEmpty {
                                Text("Related: " + item.related.prefix(3).map(\.label).joined(separator: " · "))
                                    .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct BrainMap: View {
    let items: [BrainSearchItem]

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let visible = Array(items.prefix(18))
                let positions = Dictionary(uniqueKeysWithValues: visible.enumerated().map { index, item in
                    (item.id, position(index: index, count: visible.count, size: size))
                })
                for item in visible {
                    guard let from = positions[item.id] else { continue }
                    for related in item.related.prefix(4) {
                        guard let to = positions[related.id] else { continue }
                        var path = Path(); path.move(to: from); path.addLine(to: to)
                        context.stroke(path, with: .color(.secondary.opacity(0.25)), lineWidth: 1)
                    }
                }
                for item in visible {
                    guard let point = positions[item.id] else { continue }
                    let rect = CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14)
                    context.fill(Path(ellipseIn: rect), with: .color(color(item.type)))
                    context.draw(Text(item.label).font(.caption2).foregroundColor(.primary), at: CGPoint(x: point.x, y: point.y + 16), anchor: .top)
                }
            }
        }
        .padding(26)
        .background(.quaternary.opacity(0.3))
    }

    private func position(index: Int, count: Int, size: CGSize) -> CGPoint {
        guard count > 0 else { return CGPoint(x: size.width / 2, y: size.height / 2) }
        let angle = (CGFloat(index) / CGFloat(count)) * .pi * 2 - .pi / 2
        let radius = min(size.width, size.height) * 0.34
        return CGPoint(x: size.width / 2 + CoreGraphics.cos(angle) * radius, y: size.height / 2 + CoreGraphics.sin(angle) * radius)
    }

    private func color(_ type: String) -> Color {
        switch type {
        case "recording": .orange
        case "transcript": .blue
        case "function": .green
        case "file": .purple
        case "prompt": .pink
        default: .gray
        }
    }
}
