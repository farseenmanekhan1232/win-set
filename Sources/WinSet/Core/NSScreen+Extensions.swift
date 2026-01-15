import Cocoa

extension NSScreen {
    var displayID: CGDirectDisplayID {
        return deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }
    
    /// Returns the visible frame in Accessibility API coordinate system (top-left origin).
    /// NSScreen uses bottom-left origin, but AX APIs use top-left origin.
    var visibleFrameForAX: CGRect {
        // Get the main screen's total height for coordinate conversion
        guard let mainScreen = NSScreen.screens.first else { return visibleFrame }
        let screenHeight = mainScreen.frame.height
        
        // Convert Y from bottom-left to top-left
        // In bottom-left: origin.y is distance from bottom
        // In top-left: origin.y should be distance from top
        let topLeftY = screenHeight - visibleFrame.origin.y - visibleFrame.height
        
        return CGRect(
            x: visibleFrame.origin.x,
            y: topLeftY,
            width: visibleFrame.width,
            height: visibleFrame.height
        )
    }
}
