import Foundation

/// Smart layout engine that switches between:
/// - Equal split or golden ratio for 2 windows (configurable)
/// - Golden ratio master/stack for 3 windows
/// - Grid layout for 4+ windows
/// Supports dynamic resizing by user
class LayoutEngine {

    // Golden ratio ≈ 0.618
    private static let goldenRatio: CGFloat = 0.618

    // Config
    var gaps: CGFloat = 10.0

    // Current master/stack split ratio (can be adjusted by user)
    private(set) var masterRatio: CGFloat = goldenRatio

    // Ordered list of window IDs (first = master in master/stack mode)
    private(set) var windowIds: [WindowID] = []

    init() {}

    // MARK: - Window Management

    /// Add a window to the layout
    func addWindow(_ windowId: WindowID) {
        guard !windowIds.contains(windowId) else { return }
        windowIds.append(windowId)
    }

    /// Remove a window from the layout
    func removeWindow(_ windowId: WindowID) {
        windowIds.removeAll { $0 == windowId }
    }

    /// Check if a window is in this layout
    func containsWindow(_ windowId: WindowID) -> Bool {
        return windowIds.contains(windowId)
    }

    /// Swap two windows in the layout order
    func swapWindows(_ id1: WindowID, _ id2: WindowID) {
        guard let idx1 = windowIds.firstIndex(of: id1),
              let idx2 = windowIds.firstIndex(of: id2) else { return }
        windowIds.swapAt(idx1, idx2)
    }

    /// Reorder windows to a new sequence
    func reorderWindows(_ newOrder: [WindowID]) {
        // Validate all window IDs exist
        let validIds = Set(windowIds)
        guard newOrder.count == windowIds.count,
              newOrder.allSatisfy({ validIds.contains($0) }) else {
            print("Invalid window order - must contain exactly the same window IDs")
            return
        }
        windowIds = newOrder
    }

    /// Move a window to master position (first in list)
    func promoteToMaster(_ windowId: WindowID) {
        guard let idx = windowIds.firstIndex(of: windowId), idx > 0 else { return }
        windowIds.remove(at: idx)
        windowIds.insert(windowId, at: 0)
    }

    /// Focus callback (for future use)
    func focusWindow(_ windowId: WindowID) {
        // Could be used for visual highlighting
    }

    /// Prune windows not in the valid set
    func prune(keeping validIds: Set<WindowID>) {
        windowIds.removeAll { !validIds.contains($0) }
    }

    // MARK: - Ratio Adjustment

    /// Update master ratio based on user resizing (only applies in master/stack mode)
    func updateRatioFromResize(windowId: WindowID, newFrame: CGRect, screenFrame: CGRect) -> Bool {
        // Only adjust ratio in master/stack mode (2-3 windows)
        guard windowIds.count >= 2 && windowIds.count <= 3 else { return false }

        let isMaster = windowIds.first == windowId

        if isMaster {
            let usableWidth = screenFrame.width - (gaps * 3)
            let masterWidth = newFrame.width
            let newRatio = (masterWidth / usableWidth).clamped(to: 0.3...0.8)

            if abs(newRatio - masterRatio) > 0.02 {
                masterRatio = newRatio
                return true
            }
        }

        return false
    }

    /// Reset to golden ratio
    func resetRatio() {
        masterRatio = Self.goldenRatio
    }



    // MARK: - Frame Calculation

    /// Calculate frames for all windows - automatically picks best layout
    func calculateFrames(for screenFrame: CGRect) -> [WindowID: CGRect] {
        guard !windowIds.isEmpty else { return [:] }

        switch windowIds.count {
        case 1:
            return calculateSingleWindow(for: screenFrame)
        case 2:
            // 50/50 split for 2 windows
            return calculateSplit(for: screenFrame)
        case 3:
            // Master/Stack for 3 windows
            return calculateMasterStack(for: screenFrame)
        default:
            return calculateGrid(for: screenFrame)
        }
    }

    // MARK: - Layout Algorithms

    /// Single window - full screen with gaps
    private func calculateSingleWindow(for screenFrame: CGRect) -> [WindowID: CGRect] {
        let frame = CGRect(
            x: screenFrame.origin.x + gaps,
            y: screenFrame.origin.y + gaps,
            width: screenFrame.width - (gaps * 2),
            height: screenFrame.height - (gaps * 2)
        )
        return [windowIds[0]: frame]
    }
    
    /// 2 Windows - 50/50 Split
    private func calculateSplit(for screenFrame: CGRect) -> [WindowID: CGRect] {
        var frames: [WindowID: CGRect] = [:]
        
        let usableFrame = CGRect(
            x: screenFrame.origin.x + gaps,
            y: screenFrame.origin.y + gaps,
            width: screenFrame.width - (gaps * 2),
            height: screenFrame.height - (gaps * 2)
        )
        
        let width = (usableFrame.width - gaps) / 2
        
        // Left
        frames[windowIds[0]] = CGRect(
            x: usableFrame.origin.x,
            y: usableFrame.origin.y,
            width: width,
            height: usableFrame.height
        )
        
        // Right
        frames[windowIds[1]] = CGRect(
            x: usableFrame.origin.x + width + gaps,
            y: usableFrame.origin.y,
            width: width,
            height: usableFrame.height
        )
        
        return frames
    }

    /// Master/Stack layout with golden ratio (for 3 windows)
    private func calculateMasterStack(for screenFrame: CGRect) -> [WindowID: CGRect] {
        var frames: [WindowID: CGRect] = [:]

        let usableFrame = CGRect(
            x: screenFrame.origin.x + gaps,
            y: screenFrame.origin.y + gaps,
            width: screenFrame.width - (gaps * 2),
            height: screenFrame.height - (gaps * 2)
        )

        let masterWidth = usableFrame.width * masterRatio - (gaps / 2)
        let stackWidth = usableFrame.width * (1 - masterRatio) - (gaps / 2)

        // Master window (left)
        frames[windowIds[0]] = CGRect(
            x: usableFrame.origin.x,
            y: usableFrame.origin.y,
            width: masterWidth,
            height: usableFrame.height
        )

        // Stack windows (right, split vertically)
        let stackIds = Array(windowIds.dropFirst())
        let stackCount = stackIds.count
        let stackItemHeight = (usableFrame.height - (gaps * CGFloat(stackCount - 1))) / CGFloat(stackCount)

        for (index, windowId) in stackIds.enumerated() {
            let yOffset = CGFloat(index) * (stackItemHeight + gaps)
            frames[windowId] = CGRect(
                x: usableFrame.origin.x + masterWidth + gaps,
                y: usableFrame.origin.y + yOffset,
                width: stackWidth,
                height: stackItemHeight
            )
        }

        return frames
    }

    /// Grid layout for 4+ windows
    private func calculateGrid(for screenFrame: CGRect) -> [WindowID: CGRect] {
        var frames: [WindowID: CGRect] = [:]

        let count = windowIds.count

        // Calculate optimal grid dimensions
        let (cols, rows) = optimalGrid(for: count)

        let usableWidth = screenFrame.width - (gaps * CGFloat(cols + 1))
        let usableHeight = screenFrame.height - (gaps * CGFloat(rows + 1))

        let cellWidth = usableWidth / CGFloat(cols)
        let cellHeight = usableHeight / CGFloat(rows)

        for (index, windowId) in windowIds.enumerated() {
            let col = index % cols
            let row = index / cols

            let x = screenFrame.origin.x + gaps + CGFloat(col) * (cellWidth + gaps)
            let y = screenFrame.origin.y + gaps + CGFloat(row) * (cellHeight + gaps)

            frames[windowId] = CGRect(x: x, y: y, width: cellWidth, height: cellHeight)
        }

        return frames
    }

    /// Calculate optimal grid dimensions for N windows
    /// Prefers layouts that maintain reasonable aspect ratios
    private func optimalGrid(for count: Int) -> (cols: Int, rows: Int) {
        // Handle small counts specifically for better layouts
        switch count {
        case 4:
            return (2, 2)  // 2x2 square grid
        case 5:
            // 5 windows: prefer 3 cols x 2 rows (3+2=5, fills completely)
            return (3, 2)
        case 6:
            // 6 windows: 3 cols x 2 rows (fills completely)
            return (3, 2)
        case 7:
            // 7 windows: 4 cols x 2 rows = 8 slots, 1 empty
            // Or 4 cols x 2 rows gives better aspect ratio than 3x3
            return (4, 2)
        case 8:
            // 8 windows: 4 cols x 2 rows (fills completely)
            return (4, 2)
        case 9:
            // 9 windows: 3 cols x 3 rows (fills completely)
            return (3, 3)
        case 10:
            // 10 windows: 5 cols x 2 rows = 10 slots, fills completely
            return (5, 2)
        case 11:
            // 11 windows: 4 cols x 3 rows = 12 slots, 1 empty
            // Better aspect ratio than 5x3
            return (4, 3)
        case 12:
            // 12 windows: 4 cols x 3 rows = 12 slots, fills completely
            return (4, 3)
        default:
            // For larger counts, find grid that minimizes aspect ratio distortion
            let cols = Int(ceil(sqrt(Double(count))))
            let rows = Int(ceil(Double(count) / Double(cols)))

            // Ensure we have enough slots
            if cols * rows < count {
                return (cols + 1, rows)
            }

            return (cols, rows)
        }
    }

    /// Calculate frames with one window's size preserved (for resize adaptation)
    func calculateAdaptedFrames(
        for screenFrame: CGRect,
        preservedWindow: WindowID,
        preservedFrame: CGRect
    ) -> [WindowID: CGRect] {
        guard windowIds.count >= 2 else {
            return calculateFrames(for: screenFrame)
        }
        
        guard let preservedIndex = windowIds.firstIndex(of: preservedWindow) else {
            return calculateFrames(for: screenFrame)
        }

        let usableFrame = CGRect(
            x: screenFrame.origin.x + gaps,
            y: screenFrame.origin.y + gaps,
            width: screenFrame.width - (gaps * 2),
            height: screenFrame.height - (gaps * 2)
        )

        var frames: [WindowID: CGRect] = [:]
        
        // Clamp preserved width to valid range
        let minWidth = gaps * 4
        let maxWidth = usableFrame.width - gaps - minWidth
        let preservedWidth = max(minWidth, min(preservedFrame.width, maxWidth))

        switch windowIds.count {
        case 2:
            // 2-window adaptive: preserve width of resized window
            let otherIndex = preservedIndex == 0 ? 1 : 0
            let otherWidth = usableFrame.width - preservedWidth - gaps
            
            if preservedIndex == 0 {
                // Left window preserved
                frames[windowIds[0]] = CGRect(
                    x: usableFrame.origin.x,
                    y: usableFrame.origin.y,
                    width: preservedWidth,
                    height: usableFrame.height
                )
                frames[windowIds[1]] = CGRect(
                    x: usableFrame.origin.x + preservedWidth + gaps,
                    y: usableFrame.origin.y,
                    width: otherWidth,
                    height: usableFrame.height
                )
            } else {
                // Right window preserved
                frames[windowIds[0]] = CGRect(
                    x: usableFrame.origin.x,
                    y: usableFrame.origin.y,
                    width: otherWidth,
                    height: usableFrame.height
                )
                frames[windowIds[1]] = CGRect(
                    x: usableFrame.origin.x + otherWidth + gaps,
                    y: usableFrame.origin.y,
                    width: preservedWidth,
                    height: usableFrame.height
                )
            }
            
        case 3:
            // 3-window adaptive: Master/Stack layout
            if preservedIndex == 0 {
                // Master window resized - update ratio and recalculate
                let newRatio = (preservedWidth / (usableFrame.width - gaps)).clamped(to: 0.2...0.8)
                masterRatio = newRatio
                frames = calculateMasterStack(for: screenFrame)
            } else {
                // Stack window resized - adjust stack heights
                let masterWidth = usableFrame.width * masterRatio - (gaps / 2)
                let stackWidth = usableFrame.width * (1 - masterRatio) - (gaps / 2)
                
                // Master window
                frames[windowIds[0]] = CGRect(
                    x: usableFrame.origin.x,
                    y: usableFrame.origin.y,
                    width: masterWidth,
                    height: usableFrame.height
                )
                
                // Stack windows - preserve the resized one's height
                let stackIds = Array(windowIds.dropFirst())
                let stackCount = stackIds.count
                
                // Calculate preserved window's height (clamped)
                let minHeight = gaps * 4
                let maxHeight = usableFrame.height - gaps * CGFloat(stackCount - 1) - minHeight * CGFloat(stackCount - 1)
                let preservedHeight = max(minHeight, min(preservedFrame.height, maxHeight))
                
                // Calculate remaining height for other stack windows
                let remainingHeight = usableFrame.height - preservedHeight - gaps * CGFloat(stackCount - 1)
                let otherHeight = remainingHeight / CGFloat(stackCount - 1)
                
                var yOffset: CGFloat = 0
                for (index, windowId) in stackIds.enumerated() {
                    let height: CGFloat
                    if windowId == preservedWindow {
                        height = preservedHeight
                    } else {
                        height = max(minHeight, otherHeight)
                    }
                    
                    frames[windowId] = CGRect(
                        x: usableFrame.origin.x + masterWidth + gaps,
                        y: usableFrame.origin.y + yOffset,
                        width: stackWidth,
                        height: height
                    )
                    yOffset += height + gaps
                }
            }
            
        default:
            // Grid layout - more complex
            // For now, just use standard layout and preserve the window's new size
            // This could be enhanced later to properly adjust the grid
            frames = calculateFrames(for: screenFrame)
            
            // Override the preserved window's frame
            if let originalFrame = frames[preservedWindow] {
                // Preserve width, keep position and height from layout
                frames[preservedWindow] = CGRect(
                    x: originalFrame.origin.x,
                    y: originalFrame.origin.y,
                    width: min(preservedWidth, usableFrame.width - originalFrame.origin.x + usableFrame.origin.x),
                    height: originalFrame.height
                )
            }
        }

        return frames
    }
}

// MARK: - Helpers

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
