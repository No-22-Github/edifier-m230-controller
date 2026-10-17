import AppKit
import CoreBluetooth
import M230Core

let frequencies = CustomEQ.frequencies
func hex(_ bytes: Data) -> String {
  bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
}

class Controller: NSObject, NSApplicationDelegate, NSWindowDelegate, CBCentralManagerDelegate,
  CBPeripheralDelegate
{
  var central: CBCentralManager!
  var peripheral: CBPeripheral?
  var transmit: CBCharacteristic?
  var statusItem: NSStatusItem!
  var popover = NSPopover()
  var status = ConnectionStatusField(labelWithString: "正在扫描音箱…")
  var resetButton: NSButton!
  var battery = NSTextField(labelWithString: "电量：等待读取")
  var preset = NSTextField(labelWithString: "EQ 模式：等待读取")
  var sliders: [EQFader] = []
  var values: [NSTextField] = []
  var gains: [UInt8]?
  var frameDecoder = FrameDecoder()
  var advertisedAddress: [UInt8]?
  var identity = false
  var address = false
  var eqReady = false
  var busy = false
  var logLines = [String]()
  var timer: Timer?
  var queuedGains: [Int: UInt8] = [:]
  var pendingBand: Int?
  var pendingGain: UInt8?
  var writeToken = UUID()
  var connectionToken = UUID()
  func applicationDidFinishLaunching(_ n: Notification) {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    if let button = statusItem.button {
      button.image = NSImage(
        systemSymbolName: "hifispeaker.fill", accessibilityDescription: "M230 Ⅱ 电量与均衡器")
      button.image?.isTemplate = true
      button.target = self
      button.action = #selector(togglePopover)
      button.toolTip = "M230 Ⅱ · 点击调节均衡器"
    }
    popover.behavior = .transient
    popover.animates = true
    popover.contentSize = NSSize(width: 352, height: 332)
    let content = NSViewController()
    let root = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 352, height: 332))
    root.material = .popover
    root.blendingMode = .behindWindow
    root.state = .active
    content.view = root
    popover.contentViewController = content
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 6
    stack.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
      stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
      stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
    ])
    let header = NSStackView()
    header.orientation = .horizontal
    header.spacing = 12
    let artwork = SpeakerArtworkView()
    artwork.widthAnchor.constraint(equalToConstant: 64).isActive = true
    artwork.heightAnchor.constraint(equalToConstant: 46).isActive = true
    artwork.setAccessibilityElement(true)
    artwork.setAccessibilityRole(.image)
    artwork.setAccessibilityLabel("EDIFIER M230 Ⅱ 木纹音箱")
    let titles = NSStackView()
    titles.orientation = .vertical
    titles.alignment = .leading
    titles.spacing = 5
    let title = NSTextField(labelWithString: "EDIFIER M230 Ⅱ")
    title.font = .systemFont(ofSize: 14, weight: .semibold)
    battery.font = .systemFont(ofSize: 11)
    battery.textColor = .secondaryLabelColor
    titles.addArrangedSubview(title)
    titles.addArrangedSubview(battery)
    header.addArrangedSubview(artwork)
    header.addArrangedSubview(titles)
    stack.addArrangedSubview(header)
    status.font = .systemFont(ofSize: 11)
    status.textColor = .secondaryLabelColor
    status.lineBreakMode = .byWordWrapping
    status.maximumNumberOfLines = 2
    status.widthAnchor.constraint(equalToConstant: 320).isActive = true
    stack.addArrangedSubview(status)
    let chart = EQChartView()
    chart.widthAnchor.constraint(equalToConstant: 320).isActive = true
    chart.heightAnchor.constraint(equalToConstant: 180).isActive = true
    for (i, f) in frequencies.enumerated() {
      let center = 50 + Double(i) * (248.0 / 5)
      let slider = EQFader(frame: NSRect(x: center - 14, y: 46, width: 28, height: 134))
      slider.target = self
      slider.action = #selector(changeGain(_:))
      slider.tag = i
      slider.isEnabled = false
      slider.setAccessibilityLabel("\(f) Hz 增益")
      let label = NSTextField(labelWithString: f < 1000 ? "\(f)" : "\(f/1000)k")
      label.font = .systemFont(ofSize: 10)
      label.alignment = .center
      label.textColor = .secondaryLabelColor
      label.frame = NSRect(x: center - 22, y: 27, width: 44, height: 14)
      let value = NSTextField(labelWithString: "—")
      value.alignment = .center
      value.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
      value.frame = NSRect(x: center - 22, y: 7, width: 44, height: 16)
      slider.onPreview = { [weak self] gain in self?.showGain(i, gain) }
      chart.addSubview(slider)
      chart.addSubview(label)
      chart.addSubview(value)
      sliders.append(slider)
      values.append(value)
    }
    stack.addArrangedSubview(chart)
    let footer = NSStackView()
    footer.orientation = .horizontal
    footer.spacing = 10
    footer.widthAnchor.constraint(equalToConstant: 320).isActive = true
    resetButton = NSButton(title: "归零", target: self, action: #selector(resetEQ))
    resetButton.bezelStyle = .recessed
    resetButton.controlSize = .small
    resetButton.isEnabled = false
    resetButton.toolTip = "将六个频段恢复为 0"
    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    let quit = NSButton(title: "退出", target: NSApp, action: #selector(NSApplication.terminate(_:)))
    quit.bezelStyle = .recessed
    quit.controlSize = .small
    quit.widthAnchor.constraint(equalToConstant: 44).isActive = true
    footer.addArrangedSubview(resetButton)
    footer.addArrangedSubview(spacer)
    footer.addArrangedSubview(quit)
    stack.addArrangedSubview(footer)
    status.onVisibilityChange = { [weak self] hidden in
      self?.popover.contentSize = NSSize(width: 352, height: hidden ? 300 : 332)
    }
    central = CBCentralManager(delegate: self, queue: .main)
    timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
      self?.refreshState()
    }
  }
  @objc func togglePopover() {
    if popover.isShown {
      popover.performClose(nil)
      return
    }
    guard let button = statusItem.button else { return }
    NSApp.activate(ignoringOtherApps: true)
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    popover.contentViewController?.view.window?.makeKey()
    refreshState()
  }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    if !popover.isShown { togglePopover() }
    return false
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }
  func applicationWillTerminate(_ n: Notification) {
    timer?.invalidate()
    if let p = peripheral { central.cancelPeripheralConnection(p) }
  }
  func record(_ message: String) {
    guard ProcessInfo.processInfo.environment["M230_DEBUG_LOG"] == "1" else { return }
    let line = "\(ISO8601DateFormatter().string(from:Date())) \(message)"
    print(line)
    logLines.append(line)
    if logLines.count > 500 { logLines.removeFirst() }
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("M230Controller")
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    try? logLines.joined(separator: "\n").write(
      to: base.appendingPathComponent("session.log"), atomically: true, encoding: .utf8)
  }
  func enable() {
    let ready = identity && address && eqReady
    for slider in sliders { slider.isEnabled = ready }
    resetButton?.isEnabled = ready
  }
  func invalidate() {
    identity = false
    address = false
    eqReady = false
    busy = false
    gains = nil
    transmit = nil
    pendingBand = nil
    pendingGain = nil
    queuedGains.removeAll()
    frameDecoder = FrameDecoder()
    enable()
    battery.stringValue = "电量：等待重新读取"
    preset.stringValue = "EQ 模式：待读取"
    for value in values {
      value.stringValue = "—"
      value.textColor = .secondaryLabelColor
    }
  }
  func scan() {
    central.scanForPeripherals(withServices: [CBUUID(string: "5703")])
    status.stringValue = "正在寻找音箱，请确认手机 APP 已断开…"
  }
  func centralManagerDidUpdateState(_ c: CBCentralManager) {
    record("Bluetooth state=\(c.state.rawValue)")
    if c.state == .poweredOn {
      scan()
    } else {
      invalidate()
      status.stringValue = c.state == .unauthorized ? "请在系统设置 → 隐私与安全性 → 蓝牙中允许本应用" : "蓝牙不可用，请打开电脑蓝牙"
    }
  }
  func centralManager(
    _ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData a: [String: Any],
    rssi: NSNumber
  ) {
    guard peripheral == nil, let data = a[CBAdvertisementDataManufacturerDataKey] as? Data,
      data.count >= 8, Array(data.prefix(2)) == [0xE0, 0x07]
    else { return }
    advertisedAddress = Array(data[2..<8])
    peripheral = p
    p.delegate = self
    c.stopScan()
    c.connect(p)
    status.stringValue = "正在连接音箱…"
    connectionToken = UUID()
    let token = connectionToken
    DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
      guard let self = self, self.connectionToken == token, !(self.identity && self.address) else {
        return
      }
      if let p = self.peripheral { self.central.cancelPeripheralConnection(p) }
      self.status.stringValue = "连接超时，请确认手机 APP 已断开"
    }
  }
  func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
    record("Connected \(p.identifier)")
    p.discoverServices([CBUUID(string: "48095703-1A48-11E9-AB14-D663BD873D93")])
  }
  func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
    disconnect(error)
  }
  func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?)
  { disconnect(error) }
  func disconnect(_ error: Error?) {
    record("Disconnected \(String(describing:error))")
    invalidate()
    peripheral = nil
    connectionToken = UUID()
    status.stringValue = "控制连接已断开，正在重试…"
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
      if self?.central.state == .poweredOn { self?.scan() }
    }
  }
  func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
    if let error = error {
      record("Service error \(error)")
      return
    }
    for s in p.services ?? [] { p.discoverCharacteristics(nil, for: s) }
  }
  func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
    for ch in s.characteristics ?? [] {
      if ch.uuid.uuidString.hasPrefix("48090002") { transmit = ch }
    }
    for ch in s.characteristics ?? [] {
      if ch.uuid.uuidString.hasPrefix("48090001") { p.setNotifyValue(true, for: ch) }
    }
  }
  func peripheral(
    _ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?
  ) {
    guard ch.isNotifying else {
      record("Notify error \(String(describing:error))")
      return
    }
    send(0xD8)
    later(0.3) { self.send(0xC9) }
    later(0.6) { self.send(0xC8) }
  }
  func later(_ seconds: Double, _ action: @escaping () -> Void) {
    let token = connectionToken
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
      guard self?.connectionToken == token else { return }
      action()
    }
  }
  func send(_ command: UInt8, _ payload: [UInt8] = []) {
    guard let p = peripheral, let tx = transmit else { return }
    let frame = Frame.request(command, payload: payload)
    record("TX \(hex(frame))")
    p.writeValue(frame, for: tx, type: .withResponse)
  }

  func peripheral(_ p: CBPeripheral, didWriteValueFor ch: CBCharacteristic, error: Error?) {
    if let error = error {
      record("ATT error \(error)")
      status.stringValue = "连接中断，请重新打开面板"
      eqReady = false
      busy = false
      enable()
    }
  }
  @objc func refreshState() {
    guard identity && address && !busy else { return }
    send(0xD0)
    later(0.25) { if !self.busy { self.send(0xD5) } }
    later(0.5) { if !self.busy { self.send(0x43) } }
  }
  func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
    guard error == nil, let data = ch.value else { return }
    record("RX \(hex(data))")
    for frame in frameDecoder.append(data) where frame.header == 0xBB {
      accept(frame.command, frame.payload)
    }
  }

  func accept(_ command: UInt8, _ b: [UInt8]) {
    if command == 0xC9 {
      identity = String(bytes: b, encoding: .utf8) == "EDIFIER M230 Ⅱ"
      if !identity {
        status.stringValue = "此设备不是受支持的 M230 Ⅱ"
        enable()
        return
      }
    }
    if command == 0xC8 {
      address = b.count == 6 && b == advertisedAddress
      if identity && address {
        status.stringValue = "已连接"
        refreshState()
      }
    }
    guard identity && address else { return }
    if command == 0xD0, b.count == 1, b[0] <= 100 {
      battery.stringValue = "电量：\(b[0])%"
      statusItem.button?.toolTip = "M230 Ⅱ · 电量 \(b[0])%"
    }
    if command == 0xD5, b.count == 1 { preset.stringValue = "当前音效模式：\(b[0])（设备原始编号）" }
    if command == 0x43 {
      guard let decoded = try? CustomEQ.decode(b) else {
        eqReady = false
        enable()
        status.stringValue = "设备 EQ 格式不受支持"
        return
      }
      gains = decoded
      eqReady = true
      if busy, let band = pendingBand, let desired = pendingGain {
        if decoded[band] != desired {
          queuedGains.removeAll()
          status.stringValue = "调整未生效，请重试"
        } else {
          status.stringValue = "已连接"
        }
        busy = false
        pendingBand = nil
        pendingGain = nil
        writeToken = UUID()
      }
      for i in 0..<6 {
        let shown = queuedGains[i] ?? decoded[i]
        let db = Double(shown) * 0.5 - 3
        sliders[i].doubleValue = db
        showGain(i, db)
      }
      processNextGain()

      enable()
    }
  }
  func showGain(_ band: Int, _ db: Double) {
    let number =
      db == db.rounded() ? String(format: "%.0f", abs(db)) : String(format: "%.1f", abs(db))
    values[band].stringValue = db == 0 ? "0" : (db > 0 ? "+" : "−") + number
    values[band].font = .monospacedDigitSystemFont(
      ofSize: 11, weight: db == 0 ? .regular : .semibold)
    values[band].textColor = db == 0 ? .secondaryLabelColor : .controlAccentColor
  }
  @objc func changeGain(_ slider: EQFader) {
    guard identity && address && eqReady, let old = gains else { return }
    let band = slider.tag
    let code = UInt8(max(0, min(12, Int(((slider.doubleValue + 3) * 2).rounded()))))
    if !busy && code == old[band] { return }
    showGain(band, slider.doubleValue)
    queuedGains[band] = code
    processNextGain()
  }
  @objc func resetEQ() {
    guard identity && address && eqReady else { return }
    for i in 0..<6 {
      sliders[i].doubleValue = 0
      showGain(i, 0)
      queuedGains[i] = 6
    }
    processNextGain()
  }
  func processNextGain() {
    guard !busy, identity && address && eqReady, let band = queuedGains.keys.sorted().first,
      let code = queuedGains.removeValue(forKey: band)
    else { return }
    busy = true
    pendingBand = band
    pendingGain = code
    status.stringValue = "已连接"
    guard let payload = try? CustomEQ.writePayload(band: band, code: code) else { return }
    send(0x44, payload)
    let token = UUID()
    writeToken = token
    later(0.3) { if self.busy && self.writeToken == token { self.send(0x43) } }
    later(5) {
      if self.busy && self.writeToken == token {
        self.busy = false
        self.eqReady = false
        self.queuedGains.removeAll()
        self.enable()
        self.status.stringValue = "连接无响应，请重新打开面板"
      }
    }
  }

}
let app = NSApplication.shared
let controller = Controller()
app.setActivationPolicy(.accessory)
app.delegate = controller
let menu = NSMenu()
let item = NSMenuItem()
menu.addItem(item)
let submenu = NSMenu()
submenu.addItem(
  withTitle: "退出 M230 Controller", action: #selector(NSApplication.terminate(_:)),
  keyEquivalent: "q")
item.submenu = submenu
app.mainMenu = menu
app.run()
