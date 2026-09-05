import ApplicationServices
import CoreGraphics

// Undocumented but stable-for-a-decade symbol used by every serious macOS
// window manager (yabai, AeroSpace, Rectangle) to correlate an AXUIElement
// window with its CGWindowID. See TECHNICAL.md §5b and §13 for the risk
// and the fallback if this ever stops resolving.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ outID: UnsafeMutablePointer<CGWindowID>) -> AXError

func axWindowID(_ element: AXUIElement) -> CGWindowID? {
    var wid: CGWindowID = 0
    let err = _AXUIElementGetWindow(element, &wid)
    return err == .success ? wid : nil
}
