public enum LodestarColorRole: Sendable, Equatable {
    case primary, neutral, success, warning, danger, disabled
}

public enum LodestarPresentationTone: Sendable, Equatable {
    case neutral, progress, success, warning, danger, disabled

    public var colorRole: LodestarColorRole {
        switch self {
        case .neutral, .progress: .neutral
        case .success: .success
        case .warning: .warning
        case .danger: .danger
        case .disabled: .disabled
        }
    }

    public var requiresAttention: Bool {
        self == .warning || self == .danger
    }
}

public extension StatusPillKind {
    var presentationTone: LodestarPresentationTone {
        switch self {
        case .ok: .success
        case .warn: .warning
        case .error: .danger
        case .stale: .neutral
        }
    }
}
