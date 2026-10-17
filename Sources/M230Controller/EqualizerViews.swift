import AppKit

final class ConnectionStatusField: NSTextField {
  var onVisibilityChange: ((Bool) -> Void)?
  override var stringValue: String {
    didSet {
      isHidden = stringValue == "已连接"
      onVisibilityChange?(isHidden)
    }
  }
}
final class SpeakerArtworkView: NSView {
  private let artwork = Bundle.main.url(forResource: "M230II", withExtension: "png").flatMap {
    NSImage(contentsOf: $0)
  }
  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard let artwork = artwork else { return }
    let scale = artwork.size.width / 600
    artwork.draw(
      in: NSRect(x: 0, y: (bounds.height - 38) / 2, width: 64, height: 38),
      from: NSRect(x: 48 * scale, y: 140 * scale, width: 504 * scale, height: 300 * scale),
      operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
  }
}

final class EQFader: NSControl {
  private var gain = 0.0
  var onPreview: ((Double) -> Void)?
  override var doubleValue: Double {
    get { gain }
    set {
      gain = min(3, max(-3, (newValue * 2).rounded() / 2))
      needsDisplay = true
    }
  }
  override var isEnabled: Bool { didSet { needsDisplay = true } }
  override var acceptsFirstResponder: Bool { isEnabled }
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    focusRingType = .none
    setAccessibilityElement(true)
    setAccessibilityRole(.slider)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func draw(_ dirtyRect: NSRect) {
    let center = bounds.midX
    let zero = bounds.midY
    let position = 7 + (gain + 3) / 6 * 120
    NSColor.labelColor.withAlphaComponent(isEnabled ? 0.12 : 0.06).setFill()
    NSBezierPath(
      roundedRect: NSRect(x: center - 1.5, y: 7, width: 3, height: 120), xRadius: 1.5, yRadius: 1.5
    ).fill()
    if gain != 0 {
      let color =
        gain > 0 ? NSColor.controlAccentColor : NSColor.controlAccentColor.withAlphaComponent(0.45)
      color.withAlphaComponent(isEnabled ? (gain > 0 ? 1 : 0.45) : 0.2).setFill()
      NSBezierPath(
        roundedRect: NSRect(
          x: center - 1.5, y: min(zero, position), width: 3, height: abs(position - zero)),
        xRadius: 1.5, yRadius: 1.5
      ).fill()
    }
    let knob = NSBezierPath(ovalIn: NSRect(x: center - 7, y: position - 7, width: 14, height: 14))
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    shadow.shadowBlurRadius = 2
    shadow.shadowOffset = NSSize(width: 0, height: -1)
    shadow.set()
    NSColor.controlBackgroundColor.setFill()
    knob.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSColor.separatorColor.setStroke()
    knob.lineWidth = 0.5
    knob.stroke()
  }
  private func update(_ event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    doubleValue = (point.y - 7) / 120 * 6 - 3
    onPreview?(doubleValue)
  }
  override func mouseDown(with event: NSEvent) {
    guard isEnabled else { return }
    window?.makeFirstResponder(self)
    update(event)
  }
  override func mouseDragged(with event: NSEvent) {
    guard isEnabled else { return }
    update(event)
  }
  override func mouseUp(with event: NSEvent) {
    guard isEnabled else { return }
    update(event)
    sendAction(action, to: target)
  }
  private func step(_ delta: Double) -> Bool {
    guard isEnabled else { return false }
    doubleValue += delta
    onPreview?(doubleValue)
    sendAction(action, to: target)
    return true
  }
  override func keyDown(with event: NSEvent) {
    switch event.keyCode {
    case 126, 124: _ = step(0.5)
    case 125, 123: _ = step(-0.5)
    default: super.keyDown(with: event)
    }
  }
  override func accessibilityValue() -> Any? { doubleValue }
  override func setAccessibilityValue(_ value: Any?) {
    guard isEnabled, let number = value as? NSNumber else { return }
    doubleValue = number.doubleValue
    onPreview?(doubleValue)
    sendAction(action, to: target)
  }
  override func accessibilityPerformIncrement() -> Bool { step(0.5) }
  override func accessibilityPerformDecrement() -> Bool { step(-0.5) }
}

final class EQChartView: NSView {
  override func draw(_ dirtyRect: NSRect) {
    for (y, text) in [(173.0, "+3"), (113.0, "0"), (53.0, "−3")] {
      NSColor.labelColor.withAlphaComponent(text == "0" ? 0.23 : 0.10).setStroke()
      let line = NSBezierPath()
      line.move(to: NSPoint(x: 29, y: y))
      line.line(to: NSPoint(x: 320, y: y))
      line.lineWidth = text == "0" ? 1 : 0.5
      line.stroke()
      let paragraph = NSMutableParagraphStyle()
      paragraph.alignment = .right
      (text as NSString).draw(
        in: NSRect(x: 0, y: y - 6, width: 22, height: 13),
        withAttributes: [
          .font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor,
          .paragraphStyle: paragraph,
        ])
    }
  }
}
