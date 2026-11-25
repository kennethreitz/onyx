import Foundation

/// Hold ⌘ alone long enough to show the shortcut hint sheet.
///
/// The AppKit monitor feeds events in; this machine only decides whether to
/// start or stop the timer and whether to show or hide the sheet.
public struct CommandHold: Equatable, Sendable {
    /// Seconds the Command key must be held alone before the sheet appears.
    public static let duration: TimeInterval = 2.0

    public enum Phase: Equatable, Sendable {
        case idle
        case pending
        case showing
    }

    public enum Event: Equatable, Sendable {
        /// ⌘ is down and is the only modifier.
        case commandAlone
        /// ⌘ was released.
        case commandReleased
        /// Another modifier joined, or a non-modifier key, or a mouse click.
        case cancel
        /// The hold timer fired.
        case timerFired
        /// Escape was pressed (also dismisses the sheet once it is visible).
        case escape
    }

    public enum Effect: Equatable, Sendable {
        case none
        case startTimer
        case stopTimer
        case show
        case hide
    }

    public private(set) var phase: Phase = .idle

    public init() {}

    /// Map a flagsChanged modifier set (command / shift / option / control only)
    /// onto an event. Caps Lock and Function are ignored.
    public static func flagsEvent(command: Bool, shift: Bool, option: Bool, control: Bool) -> Event {
        if command && !shift && !option && !control { return .commandAlone }
        if !command { return .commandReleased }
        return .cancel
    }

    public mutating func handle(_ event: Event) -> Effect {
        switch event {
        case .commandAlone:
            switch phase {
            case .idle:
                phase = .pending
                return .startTimer
            case .pending, .showing:
                return .none
            }
        case .commandReleased:
            switch phase {
            case .idle:
                return .none
            case .pending:
                phase = .idle
                return .stopTimer
            case .showing:
                phase = .idle
                return .hide
            }
        case .cancel:
            switch phase {
            case .idle:
                return .none
            case .pending:
                phase = .idle
                return .stopTimer
            case .showing:
                phase = .idle
                return .hide
            }
        case .timerFired:
            guard phase == .pending else { return .none }
            phase = .showing
            return .show
        case .escape:
            switch phase {
            case .idle:
                return .none
            case .pending:
                phase = .idle
                return .stopTimer
            case .showing:
                phase = .idle
                return .hide
            }
        }
    }
}
