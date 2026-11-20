import AppKit
import IOKit
import Metal
import UserNotifications


func sample() -> [Reading] {
    let keys = ["TC0P", "TC0D", "TC0E", "TC0F"]
    let cpu = keys.compactMap { key -> Reading? in
        let value = thermal_read(key)
        return value.isFinite ? Reading(id: "cpu", label: "CPU Xeon", value: value, source: "AppleSMC · \(key)") : nil
    }.first ?? Reading(id: "cpu", label: "CPU Xeon", value: nil, source: "Capteur AppleSMC inaccessible")
    var result = [cpu]
    // Match Metal's registryID to the PCI parent of each accelerator.
    let devices = MTLCopyAllDevices().sorted { $0.registryID < $1.registryID }
    for (index, device) in devices.enumerated() {
        let entry = IORegistryEntryIDMatching(device.registryID)
        let pci = IOServiceGetMatchingService(kIOMainPortDefault, entry)
        var temperature: Double?
        if pci != 0 {
            defer { IOObjectRelease(pci) }
            if let stats = IORegistryEntryCreateCFProperty(pci, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
               let number = stats["Temperature(C)"] as? NSNumber {
                let value = number.doubleValue
                if value.isFinite && value > 0 && value < 130 { temperature = value }
            }
            var iterator: io_iterator_t = 0
            if IORegistryEntryCreateIterator(pci, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS {
                defer { IOObjectRelease(iterator) }
                while true {
                    let child = IOIteratorNext(iterator)
                    if child == 0 { break }
                    if let stats = IORegistryEntryCreateCFProperty(child, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
                       let number = stats["Temperature(C)"] as? NSNumber {
                        let value = number.doubleValue
                        if value.isFinite && value > 0 && value < 130 { temperature = value }
                    }
                    IOObjectRelease(child)
                }
            }
        }
        result.append(Reading(id: "gpu.\(device.name).\(devices.prefix(index).filter { $0.name == device.name }.count)", label: "GPU \(index + 1) · \(device.name)", value: temperature, source: "Pilote Radeon · PerformanceStatistics"))
    }
    return result
}


final class Monitor: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var item: NSStatusItem!
    var timer: Timer?
    let queue = DispatchQueue(label: "fr.local.MacThermal.sensors", qos: .utility)
    var busy = false
    var readings: [Reading] = []
    var alerts = AlertState()
    var settingsWindow: NSWindow?
    var fields: [(String, NSTextField)] = []
    var fanDirectory: URL?
    var usingSystemService = false
    var fanAuthorizationRunning = false
    // AppleScript execution is serialized off the main thread so the UI and
    // heartbeat continue throughout authorization and the helper session.
    let authorizationQueue = DispatchQueue(label: "fr.local.MacThermal.authorization", qos: .utility)
    var fanState = "Ventilation : initialisation…"
    func threshold(_ reading: Reading) -> Double {
        let value = UserDefaults.standard.double(forKey: "threshold.\(reading.id)")
        return (40...110).contains(value) ? value : (reading.id == "cpu" ? 75 : 85)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        item.button?.title = "Températures…"
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        if CommandLine.arguments.contains("--install-service") {
            DispatchQueue.main.async { self.installService() }
        } else if UserDefaults.standard.bool(forKey: "fanControlUnavailable") {
            fanState = "Renfort suspendu · compatibilité SMC non validée"
        } else { startFans() }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
    }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        stopFans()
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    func startFans() {
        guard !fanAuthorizationRunning else { return }
        if connectSystemService() { return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MacThermal-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            for name in ["request", "status"] {
                FileManager.default.createFile(atPath: directory.appendingPathComponent(name).path, contents: Data((name == "request" ? "0" : "waiting").utf8), attributes: [.posixPermissions: 0o600])
            }
            fanDirectory = directory
            let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/FanAssist").path
            func shellQuote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\"'\"'") + "'" }
            let command = [helper, directory.appendingPathComponent("request").path, directory.appendingPathComponent("status").path].map(shellQuote).joined(separator: " ")
            let script = "do shell script \"" + command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\" with administrator privileges"
            fanState = "Renfort : autorisation administrateur MacThermal en attente"
            fanAuthorizationRunning = true
            authorizationQueue.async { [weak self] in
                var error: NSDictionary?
                let appleScript = NSAppleScript(source: script)
                let result = appleScript?.executeAndReturnError(&error)
                let errorNumber = error?[NSAppleScript.errorNumber] as? Int
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    let status = (try? String(contentsOf: directory.appendingPathComponent("status"), encoding: .utf8)) ?? ""
                    self.fanState = status == "restore-error" ? "Ventilation : restauration échouée — redémarrer le Mac" : "Renfort indisponible ou arrêté · régulation Apple"
                    if status == "unsupported" || status == "restore-error" {
                        UserDefaults.standard.set(true, forKey: "fanControlUnavailable")
                        if status == "unsupported" { self.fanState = "Renfort refusé par le SMC · mode automatique vérifié" }
                    }
                    if errorNumber == -128 {
                        self.fanState = "Renfort non autorisé · ventilation automatique Apple"
                    } else if result == nil && status == "waiting" {
                        self.fanState = "Autorisation MacThermal échouée · ventilation automatique Apple"
                    }
                    self.fanAuthorizationRunning = false
                    if status == "restore-error" {
                        let alert = NSAlert(); alert.messageText = "Restauration des ventilateurs échouée"
                        alert.informativeText = "Le retour au mode automatique n’a pas pu être confirmé par lecture du SMC. Redémarrez le Mac pour réinitialiser la régulation. Le renfort automatique est suspendu."
                        alert.runModal()
                    }
                }
            }
        } catch {
            fanAuthorizationRunning = false; fanState = "Renfort indisponible : \(error.localizedDescription)"
        }
    }
    func connectSystemService() -> Bool {
        let directory = URL(fileURLWithPath: "/Library/Application Support/MacThermal/\(getuid())", isDirectory: true)
        let daemon = "/Library/LaunchDaemons/fr.local.MacThermal.fans.plist"
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: daemon),
              (attributes[.ownerAccountID] as? NSNumber)?.intValue == 0,
              FileManager.default.isWritableFile(atPath: directory.appendingPathComponent("request").path) else { return false }
        fanDirectory = directory; usingSystemService = true; fanAuthorizationRunning = true
        fanState = "Service système connecté · ventilation automatique Apple"
        try? Data("0".utf8).write(to: directory.appendingPathComponent("request"))
        return true
    }
    func stopFans() {
        if let directory = fanDirectory {
            let request = directory.appendingPathComponent("request")
            if usingSystemService {
                try? Data("0".utf8).write(to: request)
                try? FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: request.path)
            } else { try? FileManager.default.removeItem(at: request) }
        }
        fanDirectory = nil; usingSystemService = false
    }
    @objc func installService() {
        stopFans()
        guard let scriptURL = Bundle.main.url(forResource: "install-service", withExtension: "sh") else { return }
        let command = "/bin/bash '" + scriptURL.path.replacingOccurrences(of: "'", with: "'\"'\"'") + "' \(getuid())"
        let script = "do shell script \"" + command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\" with administrator privileges"
        fanState = "Installation du service · autorisation MacThermal en attente"
        fanAuthorizationRunning = true
        authorizationQueue.async {
            var error: NSDictionary?
            let result = NSAppleScript(source: script)?.executeAndReturnError(&error)
            let message = error?[NSAppleScript.errorMessage] as? String
            DispatchQueue.main.async {
                self.fanAuthorizationRunning = false
                if result != nil {
                    UserDefaults.standard.set(false, forKey: "fanControlUnavailable")
                    self.startFans()
                } else {
                    self.fanState = "Service non installé · ventilation automatique Apple"
                    let alert = NSAlert();alert.messageText = "Installation du service non terminée"
                    alert.informativeText = message ?? "Autorisation administrateur refusée."
                    alert.runModal()
                }
            }
        }
    }
    func refresh() {
        guard !busy else { return }; busy = true
        queue.async {
            let readings = sample()
            DispatchQueue.main.async { self.consume(readings); self.busy = false }
        }
    }
    func consume(_ values: [Reading]) {
        readings = values
        let events = alerts.update(values, threshold: threshold)
        for reading in events {
            NSSound.beep()
            let content = UNMutableNotificationContent()
            content.title = "Température élevée · \(reading.label)"
            content.body = "\(reading.formatted) — seuil \(Int(threshold(reading))) °C."
            content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "thermal.\(reading.id)", content: content, trigger: nil))
        }
        if let directory = fanDirectory {
            let status = (try? String(contentsOf: directory.appendingPathComponent("status"), encoding: .utf8)) ?? ""
            if ["ready", "boost", "boost-max", "safety-auto"].contains(status) {
                switch status {
                case "boost": fanState = "Renfort actif · consignes temporaires +20 % de la plage"
                case "boost-max": fanState = "Renfort maximal · forte température"
                case "safety-auto": fanState = "Régulation Apple · sécurité capteur CPU"
                default: fanState = "Renfort prêt · ventilation automatique Apple"
                }
            }
            if usingSystemService && ["unsupported", "restore-error", "preflight-error"].contains(status) {
                fanState = status == "restore-error" ? "Service : retour automatique non confirmé" : "Service : renfort suspendu · contrôle SMC refusé"
            }
            // Missing readings return control to Apple, which has additional sensors.
            let complete = !values.isEmpty && values.allSatisfy { $0.value != nil }
            let severe = values.contains { reading in
                guard let value = reading.value else { return false }
                return value >= min(threshold(reading) + 10, reading.id == "cpu" ? 80 : 95)
            }
            let demand = !complete || alerts.hot.isEmpty ? "0" : (severe ? "2" : "1")
            try? Data(demand.utf8).write(to: directory.appendingPathComponent("request"))
        }
        render()
    }
    func render() {
        let title = NSMutableAttributedString(string: "")
        for (index, reading) in readings.enumerated() {
            if index > 0 { title.append(NSAttributedString(string: "  ")) }
            let name = index == 0 ? "CPU" : "G\(index)"
            let temperature = reading.value.map { String(format: "%.0f°", $0) } ?? "—"
            let isHot = alerts.hot.contains(reading.id)
            title.append(NSAttributedString(string: "\(isHot ? "⚠︎ " : "")\(name) \(temperature)", attributes: [
                .foregroundColor: isHot ? NSColor.systemRed : NSColor.labelColor,
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: isHot ? .bold : .medium)
            ]))
        }
        item.button?.contentTintColor = nil
        item.button?.attributedTitle = title
        item.button?.toolTip = readings.map { "\($0.label) : \($0.formatted)" }.joined(separator: "\n")
        let menu = NSMenu()
        for reading in readings {
            let row = NSMenuItem(title: "\(reading.label) : \(reading.formatted) · seuil \(Int(threshold(reading))) °C", action: nil, keyEquivalent: "")
            if alerts.hot.contains(reading.id) {
                row.attributedTitle = NSAttributedString(string: "⚠︎ " + row.title, attributes: [.foregroundColor: NSColor.systemRed, .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)])
            }
            row.toolTip = reading.source; menu.addItem(row)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: fanState, action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Ventilateurs du Mac : " + (0..<4).map { i in
            let rpm = smc_read_number("F\(i)Ac")
            return rpm.isFinite ? "\(Int(rpm))" : "—"
        }.joined(separator: " / ") + " tr/min", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Actualisation : 3 s · réarmement à seuil − 5 °C", action: nil, keyEquivalent: ""))
        let settings = NSMenuItem(title: "Régler les seuils…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self; menu.addItem(settings)
        if !fanAuthorizationRunning {
            let retry = NSMenuItem(title: "Autoriser le renfort des ventilateurs…", action: #selector(retryFans), keyEquivalent: "")
            retry.target = self; menu.addItem(retry)
        }
        if !usingSystemService {
            let install = NSMenuItem(title: "Installer le service sans saisie aux lancements suivants…", action: #selector(installService), keyEquivalent: "")
            install.target = self; menu.addItem(install)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quitter MacThermal", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }
    @objc func retryFans() { startFans() }
    @objc func showSettings() {
        if let window = settingsWindow { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil); return }
        let height = 175 + readings.count * 55
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 530, height: height), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "MacThermal · seuils d’alerte"; window.isReleasedWhenClosed = false
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 22), stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -22), stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 22)])
        fields = []
        for reading in readings {
            let row = NSStackView(); row.orientation = .horizontal; row.spacing = 12
            let label = NSTextField(labelWithString: reading.label)
            label.widthAnchor.constraint(equalToConstant: 350).isActive = true
            let field = NSTextField(string: String(Int(threshold(reading))))
            field.widthAnchor.constraint(equalToConstant: 55).isActive = true
            fields.append((reading.id, field))
            row.addArrangedSubview(label); row.addArrangedSubview(field); row.addArrangedSubview(NSTextField(labelWithString: "°C"));stack.addArrangedSubview(row)
        }
        let note = NSTextField(wrappingLabelWithString: "Valeurs de 40 à 110 °C. CPU : capteur de proximité, pas le cœur le plus chaud. Alerte visuelle et sonore ; notifications si autorisées dans macOS. Retour au mode automatique Apple sous seuil − 5 °C.")
        note.font = .systemFont(ofSize: 12); stack.addArrangedSubview(note)
        let button = NSButton(title: "Enregistrer", target: self, action: #selector(saveSettings));stack.addArrangedSubview(button)
        settingsWindow = window; window.center(); NSApp.activate(ignoringOtherApps: true);window.makeKeyAndOrderFront(nil)
    }
    @objc func saveSettings() {
        var changes: [(String, Double)] = []
        for (id, field) in fields {
            guard let value = Double(field.stringValue), value.isFinite, (40...110).contains(value) else {
                let alert = NSAlert(); alert.messageText = "Saisissez un seuil entre 40 et 110 °C.";alert.runModal();return
            }
            changes.append((id, value))
        }
        for (id, value) in changes { UserDefaults.standard.set(value, forKey: "threshold.\(id)") }
        alerts = AlertState();settingsWindow?.close();settingsWindow = nil;consume(readings)
    }
}

if CommandLine.arguments.contains("--self-test") {
    func r(_ id: String, _ value: Double?) -> Reading { Reading(id: id, label: id, value: value, source: "test") }
    var state = AlertState()
    assert(state.update([r("cpu", 74), r("gpu", 84)], threshold: { $0.id == "cpu" ? 75 : 85 }).isEmpty)
    assert(state.update([r("cpu", 75), r("gpu", 85)], threshold: { $0.id == "cpu" ? 75 : 85 }).count == 2)
    assert(state.update([r("cpu", 73), r("gpu", nil)], threshold: { $0.id == "cpu" ? 75 : 85 }).isEmpty)
    assert(state.hot.count == 2)
    _ = state.update([r("cpu", 70), r("gpu", 80)], threshold: { $0.id == "cpu" ? 75 : 85 })
    assert(state.hot.isEmpty)
    assert(state.update([r("cpu", 76)], threshold: { _ in 75 }).count == 1)
    print("OK : seuils indépendants, hystérésis, absence de répétition, capteur indisponible, réarmement")
} else if CommandLine.arguments.contains("--diagnostic") {
    for reading in sample() { print("\(reading.label) : \(reading.formatted) [\(reading.source)]") }
} else {
    let app = NSApplication.shared
    let delegate = Monitor()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
