import Foundation

/// A node in the Binary Space Partitioning tree
enum BSPNode: Codable {
    case split(Split)
    case window(WindowID)
    
    struct Split: Codable {
        let type: SplitType
        var ratio: CGFloat // 0.0 to 1.0 (typically 0.5)
        var child1: Box<BSPNode>
        var child2: Box<BSPNode>
    }
    
    enum SplitType: String, Codable {
        case horizontal // Split vertically (left/right) - confusing name convention, often called vertical split in some WMs
        case vertical   // Split horizontally (top/bottom)
        
        // Let's clarify:
        // Horizontal Split = Two windows side-by-side [ | ]
        // Vertical Split = Two windows top-bottom [ - ]
    }
}

// Helper to allow recursive structs in Swift enums
class Box<T: Codable>: Codable {
    var value: T
    init(_ value: T) { self.value = value }
}

/// Pure logic engine for calculating window frames based on BSP tree
class LayoutEngine {
    
    private(set) var root: BSPNode?
    
    // Config
    var gaps: CGFloat = 10.0
    
    // State
    // Track all window IDs in this engine for O(1) lookup
    private(set) var windowIds: Set<WindowID> = []
    
    // We also need to know the "Last Focused" node to determine where to split.
    var lastFocusedWindowId: WindowID?
    
    init() {}
    
    // MARK: - Operations
    
    /// Check if a window is tracked by this engine
    func containsWindow(_ windowId: WindowID) -> Bool {
        return windowIds.contains(windowId)
    }
    
    /// Add a new window to the tree (idempotent - skips if already exists)
    func addWindow(_ windowId: WindowID) {
        // Idempotency check
        guard !windowIds.contains(windowId) else {
            print("LayoutEngine: Window \(windowId) already in tree, skipping add")
            return
        }
        
        windowIds.insert(windowId)
        
        guard let root = root else {
            // First window becomes root
            self.root = .window(windowId)
            return
        }
        
        // If we have a focus expectation AND that window exists in our tree, insert relative to it.
        // Otherwise, find a leaf.
        
        if let focusedId = lastFocusedWindowId, windowIds.contains(focusedId) {
            self.root = insert(windowId, relativeTo: focusedId, in: root)
        } else {
            // No valid focus, just split the first leaf we find
            self.root = insertAtAnyLeaf(windowId, in: root)
        }
    }
    
    /// Remove a window from the tree
    func removeWindow(_ windowId: WindowID) {
        guard windowIds.contains(windowId) else {
            return
        }
        
        windowIds.remove(windowId)
        
        // Update lastFocusedWindowId if we're removing it
        if lastFocusedWindowId == windowId {
            lastFocusedWindowId = windowIds.first
        }
        
        guard let root = root else { return }
        
        if case .window(let id) = root, id == windowId {
            self.root = nil
            return
        }
        
        self.root = remove(windowId, from: root)
    }
    
    /// Swap two windows in the tree
    func swapWindows(_ id1: WindowID, _ id2: WindowID) {
        guard windowIds.contains(id1), windowIds.contains(id2) else {
            return
        }
        guard let root = root else { return }
        
        // Use a placeholder to perform the swap
        let placeholder: WindowID = UInt32.max
        self.root = replaceWindow(id1, with: placeholder, in: root)
        self.root = replaceWindow(id2, with: id1, in: self.root!)
        self.root = replaceWindow(placeholder, with: id2, in: self.root!)
        
        print("LayoutEngine: Swapped windows \(id1) <-> \(id2)")
    }
    
    private func replaceWindow(_ targetId: WindowID, with newId: WindowID, in node: BSPNode) -> BSPNode {
        switch node {
        case .window(let id):
            return id == targetId ? .window(newId) : node
        case .split(let split):
            var newSplit = split
            newSplit.child1 = Box(replaceWindow(targetId, with: newId, in: split.child1.value))
            newSplit.child2 = Box(replaceWindow(targetId, with: newId, in: split.child2.value))
            return .split(newSplit)
        }
    }
    
    /// Update the split ratio for the container of a window
    /// newRatio: The desired ratio for child1 (the left/top window)
    func updateSplitRatio(for windowId: WindowID, newRatio: CGFloat) {
        guard windowIds.contains(windowId), let root = root else { return }
        
        // Find the split that contains this window and update its ratio
        self.root = updateSplitRatioRecursive(windowId, newRatio: newRatio, in: root)
        print("LayoutEngine: Updated split ratio for \(windowId) to \(newRatio)")
    }
    
    private func updateSplitRatioRecursive(_ targetId: WindowID, newRatio: CGFloat, in node: BSPNode) -> BSPNode {
        switch node {
        case .window:
            return node  // Not a split, return as-is
            
        case .split(let split):
            // Check if this split directly contains our target window
            let child1ContainsTarget = containsWindowInNode(targetId, in: split.child1.value)
            let child2ContainsTarget = containsWindowInNode(targetId, in: split.child2.value)
            
            if child1ContainsTarget && !child2ContainsTarget {
                // Target is in child1 - this is the split we want to modify
                // If target is child1, use newRatio directly
                if case .window(let id) = split.child1.value, id == targetId {
                    var newSplit = split
                    newSplit.ratio = newRatio
                    return .split(newSplit)
                }
                // Target is deeper in child1, recurse
                var newSplit = split
                newSplit.child1 = Box(updateSplitRatioRecursive(targetId, newRatio: newRatio, in: split.child1.value))
                return .split(newSplit)
                
            } else if child2ContainsTarget && !child1ContainsTarget {
                // Target is in child2 - update ratio (inverted since it's child2)
                if case .window(let id) = split.child2.value, id == targetId {
                    var newSplit = split
                    newSplit.ratio = 1.0 - newRatio  // Invert for child2
                    return .split(newSplit)
                }
                // Target is deeper in child2, recurse
                var newSplit = split
                newSplit.child2 = Box(updateSplitRatioRecursive(targetId, newRatio: newRatio, in: split.child2.value))
                return .split(newSplit)
            }
            
            // Neither or both contain target - just return as-is (shouldn't happen)
            return node
        }
    }
    
    private func containsWindowInNode(_ windowId: WindowID, in node: BSPNode) -> Bool {
        switch node {
        case .window(let id):
            return id == windowId
        case .split(let split):
            return containsWindowInNode(windowId, in: split.child1.value) ||
                   containsWindowInNode(windowId, in: split.child2.value)
        }
    }
    
    /// Calculate frames for all windows in the tree given a screen rect
    func calculateFrames(for screenFrame: CGRect) -> [WindowID: CGRect] {
        var frames: [WindowID: CGRect] = [:]
        guard let root = root else { return frames }
        
        // Apply outer gaps
        let paddedFrame = screenFrame.insetBy(dx: gaps, dy: gaps)
        
        traverse(node: root, frame: paddedFrame) { id, rect in
            frames[id] = rect
        }
        
        return frames
    }
    
    // MARK: - internal Logic
    
    // MARK: - Pruning
    
    /// Prune windows that are no longer in the set of valid IDs
    func prune(keeping validIds: Set<WindowID>) {
        // Find windows to remove
        let toRemove = windowIds.subtracting(validIds)
        
        for id in toRemove {
            removeWindow(id)
        }
    }
    
    private func insert(_ newId: WindowID, relativeTo targetId: WindowID, in node: BSPNode) -> BSPNode {
        switch node {
        case .window(let id):
            if id == targetId {
                // Found the target! Split it.
                // Todo: Determine split direction based on aspect ratio?
                // Default: Horizontal split (Side-by-side)
                let newSplit = BSPNode.Split(
                    type: .horizontal,
                    ratio: 0.5,
                    child1: Box(.window(targetId)), // Keep original on left/top
                    child2: Box(.window(newId))     // New on right/bottom
                )
                return .split(newSplit)
            } else {
                return node
            }
            
        case .split(let split):
            // Recurse
            let newC1 = insert(newId, relativeTo: targetId, in: split.child1.value)
            let newC2 = insert(newId, relativeTo: targetId, in: split.child2.value)
            
            // Check if anything changed (not strictly necessary but clear)
            // Ideally we'd know which path to take. Here we traverse both which is O(N). Fine for <100 windows.
            // Actually capturing "did insert" return might be cleaner but this works for replacement.
            
            var newSplit = split
            newSplit.child1 = Box(newC1)
            newSplit.child2 = Box(newC2)
            return .split(newSplit)
        }
    }
    
    private func insertAtAnyLeaf(_ newId: WindowID, in node: BSPNode) -> BSPNode {
        switch node {
        case .window(let id):
            // Split this leaf
            let newSplit = BSPNode.Split(
                type: .horizontal,
                ratio: 0.5,
                child1: Box(.window(id)),
                child2: Box(.window(newId))
            )
            return .split(newSplit)
            
        case .split(let split):
            // Prefer left child? Or smaller child?
            // Simple: Left child.
            let newC1 = insertAtAnyLeaf(newId, in: split.child1.value)
            var newSplit = split
            newSplit.child1 = Box(newC1)
            return .split(newSplit)
        }
    }
    
    private func remove(_ targetId: WindowID, from node: BSPNode) -> BSPNode? {
        switch node {
        case .window(let id):
            return id == targetId ? nil : node
            
        case .split(let split):
            let newC1 = remove(targetId, from: split.child1.value)
            let newC2 = remove(targetId, from: split.child2.value)
            
            // If one child became nil, replace this split with the remaining child
            if newC1 == nil, let rem = newC2 {
                return rem
            }
            if newC2 == nil, let rem = newC1 {
                return rem
            }
            // If both nil, we are nil
            if newC1 == nil && newC2 == nil {
                return nil
            }
            
            // Update children
            var newSplit = split
            if let c1 = newC1 { newSplit.child1 = Box(c1) }
            if let c2 = newC2 { newSplit.child2 = Box(c2) }
            return .split(newSplit)
        }
    }
    
    private func traverse(node: BSPNode, frame: CGRect, action: (WindowID, CGRect) -> Void) {
        switch node {
        case .window(let id):
            // Apply inner gaps?
            // With outer gaps handled, inner gaps are trickier in BSP.
            // Simple Inner Gap: Inset every window by gap/2
            let innerPadded = frame.insetBy(dx: gaps/2, dy: gaps/2)
            action(id, innerPadded)
            
        case .split(let split):
            var f1 = frame
            var f2 = frame
            
            // Calculate divisor
            // Note: coordinates are top-left usually for layouts.
            
            if split.type == .horizontal {
                // Side by side
                let splitX = frame.width * split.ratio
                f1.size.width = splitX
                f2.origin.x += splitX
                f2.size.width = frame.width - splitX
            } else {
                // Top and bottom
                let splitY = frame.height * split.ratio
                f1.size.height = splitY
                f2.origin.y += splitY
                f2.size.height = frame.height - splitY
            }
            
            traverse(node: split.child1.value, frame: f1, action: action)
            traverse(node: split.child2.value, frame: f2, action: action)
        }
    }
    
    // MARK: - Helpers
    
    func focusWindow(_ id: WindowID) {
        lastFocusedWindowId = id
    }
    
    func printTree() {
        printNode(root, depth: 0)
    }
    
    private func printNode(_ node: BSPNode?, depth: Int) {
        let prefix = String(repeating: "  ", count: depth)
        guard let node = node else {
            print("\(prefix)(nil)")
            return
        }
        
        switch node {
        case .window(let id):
            print("\(prefix)Window[\(id)]")
        case .split(let split):
            print("\(prefix)Split(\(split.type) @ \(split.ratio))")
            printNode(split.child1.value, depth: depth + 1)
            printNode(split.child2.value, depth: depth + 1)
        }
    }
}
