import Foundation

public enum BrainBrowserSection: String, Equatable, Sendable, Identifiable {
    case home
    case all
    case recording
    case transcript
    case session
    case memory
    case document
    case project
    case file
    case function
    case search

    public var id: String { rawValue }

    public static let sidebarSections: [BrainBrowserSection] = [
        .home, .all, .recording, .transcript, .session, .memory, .document, .project, .file, .function,
    ]

    public var browseType: String? {
        switch self {
        case .home, .search: nil
        case .all: "all"
        default: rawValue
        }
    }

    public var title: String {
        switch self {
        case .home: "Home"
        case .all: "All Sources"
        case .recording: "Recordings"
        case .transcript: "Transcripts"
        case .session: "Agent Sessions"
        case .memory: "Memories"
        case .document: "Documents"
        case .project: "Repositories"
        case .file: "Files"
        case .function: "Functions"
        case .search: "Search Results"
        }
    }

    public var systemImage: String {
        switch self {
        case .home: "house"
        case .all: "square.stack.3d.up"
        case .recording: "waveform"
        case .transcript: "text.quote"
        case .session: "bubble.left.and.bubble.right"
        case .memory: "brain"
        case .document: "doc.text"
        case .project: "shippingbox"
        case .file: "doc"
        case .function: "function"
        case .search: "magnifyingglass"
        }
    }
}

public struct BrainRelatedItem: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let type: String
    public let label: String
    public let path: String?
}

public struct BrainSearchItem: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let type: String
    public let label: String
    public let path: String?
    public let score: Double
    public let excerpt: String
    public let related: [BrainRelatedItem]
}

public struct BrainSearchResponse: Codable, Equatable, Sendable {
    public let query: String
    public let results: [BrainSearchItem]
}

public struct BrainStats: Codable, Equatable, Sendable {
    public let graphPath: String
    public let nodes: Int
    public let edges: Int
    public let nodeTypes: [String: Int]
    public let repository: String?
    public let language: String?
    public let files: Int?
    public let functions: Int?
}

public struct BrainManagedRefresh: Codable, Equatable, Sendable {
    public let due: Bool
    public let checked: Int
    public let updated: Int
    public let unchanged: Int
    public let failed: Int
}

public struct BrainManagedRefreshResponse: Codable, Equatable, Sendable {
    public let repositories: BrainManagedRefresh
}

public struct BrainHermesImport: Codable, Equatable, Sendable {
    public let documents: Int
    public let memories: Int
    public let sessions: Int
    public let turns: Int
}

public struct BrainHermesSyncResponse: Codable, Equatable, Sendable {
    public let graphPath: String
    public let nodes: Int
    public let edges: Int
    public let nodeTypes: [String: Int]
    public let imported: BrainHermesImport
}
