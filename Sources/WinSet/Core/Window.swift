import Cocoa
import ApplicationServices

/// Unique identifier for a window
typealias WindowID = CGWindowID

/// Direction for spatial navigation
enum Direction: String, CaseIterable {
    case left, down, up, right
    
    var opposite: Direction {
        switch self {
        case .left: return .right
        case .right: return .left
        case .up: return .down
        case .down: return .up
        }
    }
}

/// Screen position for window snapping
enum SnapPosition: String, CaseIterable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case center
    case maximize
    
    /// Calculate frame for this snap position on given screen
    func frame(on screen: NSScreen, gaps: CGFloat = 10) -> CGRect {
        let visibleFrame = screen.visibleFrame
        let halfWidth = (visibleFrame.width - gaps * 3) / 2
        let halfHeight = (visibleFrame.height - gaps * 3) / 2
        
        switch self {
        case .leftHalf:
            return CGRect(
                x: visibleFrame.minX + gaps,
                y: visibleFrame.minY + gaps,
                width: halfWidth,
                height: visibleFrame.height - gaps * 2
            )
        case .rightHalf:
            return CGRect(
                x: visibleFrame.midX + gaps / 2,
                y: visibleFrame.minY + gaps,
                width: halfWidth,
                height: visibleFrame.height - gaps * 2
            )
        case .topHalf:
            return CGRect(
                x: visibleFrame.minX + gaps,
                y: visibleFrame.midY + gaps / 2,
                width: visibleFrame.width - gaps * 2,
                height: halfHeight
            )
        case .bottomHalf:
            return CGRect(
                x: visibleFrame.minX + gaps,
                y: visibleFrame.minY + gaps,
                width: visibleFrame.width - gaps * 2,
                height: halfHeight
            )
        case .topLeft:
            return CGRect(
                x: visibleFrame.minX + gaps,
                y: visibleFrame.midY + gaps / 2,
                width: halfWidth,
                height: halfHeight
            )
        case .topRight:
            return CGRect(
                x: visibleFrame.midX + gaps / 2,
                y: visibleFrame.midY + gaps / 2,
                width: halfWidth,
                height: halfHeight
            )
        case .bottomLeft:
            return CGRect(
                x: visibleFrame.minX + gaps,
                y: visibleFrame.minY + gaps,
                width: halfWidth,
                height: halfHeight
            )
        case .bottomRight:
            return CGRect(
                x: visibleFrame.midX + gaps / 2,
                y: visibleFrame.minY + gaps,
                width: halfWidth,
                height: halfHeight
            )
        case .center:
            let width = visibleFrame.width * 0.6
            let height = visibleFrame.height * 0.7
            return CGRect(
                x: visibleFrame.midX - width / 2,
                y: visibleFrame.midY - height / 2,
                width: width,
                height: height
            )
        case .maximize:
            return CGRect(
                x: visibleFrame.minX + gaps,
                y: visibleFrame.minY + gaps,
                width: visibleFrame.width - gaps * 2,
                height: visibleFrame.height - gaps * 2
            )
        }
    }
}

/// Represents a window on screen
struct Window: Identifiable, Equatable {
    let id: WindowID
    let axElement: AXUIElement
    var frame: CGRect
    var title: String
    var appName: String
    var appPID: pid_t
    var isMinimized: Bool
    var isFullscreen: Bool
    
    /// Center point of the window
    var center: CGPoint {
        CGPoint(x: frame.midX, y: frame.midY)
    }
    
    /// Check if this window is in the given direction relative to another window
    /// Check if this window is in the given direction relative to another window
    func isInDirection(_ direction: Direction, from other: Window) -> Bool {
        switch direction {
        case .left:
            return center.x < other.center.x
        case .right:
            return center.x > other.center.x
        case .up:
            // AX coordinates have origin at top-left, so up means smaller Y
            return center.y < other.center.y
        case .down:
            // AX coordinates: down means larger Y
            return center.y > other.center.y
        }
    }
    
    /// Distance to another window (for finding nearest)
    func distance(to other: Window) -> CGFloat {
        let dx = center.x - other.center.x
        let dy = center.y - other.center.y
        return sqrt(dx * dx + dy * dy)
    }
    
    static func == (lhs: Window, rhs: Window) -> Bool {
        lhs.id == rhs.id
    }
}
