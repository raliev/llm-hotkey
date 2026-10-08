import Cocoa
import Carbon
import CoreGraphics
import AVFoundation
import NaturalLanguage

// text_hotkey — select text in any app, press a hotkey, the selection is replaced
// by the LLM's result (translate / grammar / rephrase) or read aloud (speak).
//
// Hotkeys are registered via Carbon RegisterEventHotKey (same as voice-rec's
// screenshot_helper): no CGEventTap, so nothing can time out or get disabled
// by the system. Accessibility permission is only needed to post Cmd+C / Cmd+V.
//
// Config: ~/.config/text-hotkey/config.json (created with defaults on first run).
// API keys may also come from OPENAI_API_KEY / GEMINI_API_KEY.

// ── Config ───────────────────────────────────────────────────────────────────

struct Action {
    let name: String
    let hotkeys: [String]
    let prompt: String      // empty for "speak"
}

let configDir = (NSHomeDirectory() as NSString).appendingPathComponent(".config/text-hotkey")
let configPath = (configDir as NSString).appendingPathComponent("config.json")

let defaultConfig: [String: Any] = [
    "provider": "openai",
    "openai_api_key": "",
    "openai_model": "gpt-4.1",
    "gemini_api_key": "",
    "gemini_model": "gemini-2.5-flash",
    "restore_clipboard": true,
    "actions": [
        "translate": [
            "hotkeys": ["cmd+opt+t", "f5"],
            "prompt": "Translate the user's text. If it is in Russian, translate it into English; otherwise translate it into Russian. Preserve formatting, line breaks and tone. Return only the translated text, without quotes or comments.",
        ],
        "grammar": [
            "hotkeys": ["cmd+opt+g", "f6"],
            "prompt": "Correct grammatical, spelling and punctuation errors in the user's text. Do not change the text if there are no errors; if there are, change it minimally. Keep the original language and formatting. Return only the corrected text, without quotes or comments.",
        ],
        "rephrase": [
            "hotkeys": ["cmd+opt+r"],
            "prompt": "Rephrase the user's text to make it clearer and more natural, keeping its meaning, language and approximate length. Return only the rephrased text, without quotes or comments.",
        ],
        "speak": [
            "hotkeys": ["cmd+opt+s"],
        ],
    ],
]

var config: [String: Any] = [:]

func loadConfig() {
    let fm = FileManager.default
    if !fm.fileExists(atPath: configPath) {
        try? fm.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: defaultConfig, options: [.prettyPrinted, .sortedKeys]) {
            fm.createFile(atPath: configPath, contents: data, attributes: [.posixPermissions: 0o600])
        }
        log("created default config at \(configPath)")
    }
    var c = defaultConfig
    if let data = fm.contents(atPath: configPath) {
        do {
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                c.merge(obj) { _, new in new }
            }
        } catch {
            log("config parse error: \(error.localizedDescription) — using defaults")
        }
    }
    config = c
}

func saveProvider(_ provider: String) {
    guard let data = FileManager.default.contents(atPath: configPath),
          var obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
    obj["provider"] = provider
    if let out = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
        try? out.write(to: URL(fileURLWithPath: configPath))
    }
}

func cfg(_ key: String) -> String { config[key] as? String ?? "" }

func apiKey(_ provider: String) -> String {
    let fromConfig = cfg("\(provider)_api_key")
    if !fromConfig.isEmpty { return fromConfig }
    return ProcessInfo.processInfo.environment["\(provider.uppercased())_API_KEY"] ?? ""
}

func actions() -> [Action] {
    let defaults = defaultConfig["actions"] as! [String: [String: Any]]
    let user = config["actions"] as? [String: [String: Any]] ?? [:]
    return defaults.keys.sorted().map { name in
        let a = user[name] ?? defaults[name]!
        return Action(name: name,
                      hotkeys: a["hotkeys"] as? [String] ?? [],
                      prompt: a["prompt"] as? String ?? (defaults[name]!["prompt"] as? String ?? ""))
    }
}

func log(_ s: String) {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    fputs("[\(f.string(from: Date()))] \(s)\n", stderr)
}

// ── Hotkey parsing ───────────────────────────────────────────────────────────

let keyCodes: [String: Int] = [
    "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E,
    "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J,
    "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
    "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
    "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y,
    "z": kVK_ANSI_Z,
    "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
    "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
    "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5, "f6": kVK_F6,
    "f7": kVK_F7, "f8": kVK_F8, "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12,
    "f13": kVK_F13, "f14": kVK_F14, "f15": kVK_F15, "f16": kVK_F16, "f17": kVK_F17,
    "f18": kVK_F18, "f19": kVK_F19,
    "space": kVK_Space, "return": kVK_Return, "escape": kVK_Escape,
    "`": kVK_ANSI_Grave, "-": kVK_ANSI_Minus, "=": kVK_ANSI_Equal,
    "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket, ";": kVK_ANSI_Semicolon,
    "'": kVK_ANSI_Quote, ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period, "/": kVK_ANSI_Slash,
    "\\": kVK_ANSI_Backslash,
]

func parseHotkey(_ s: String) -> (UInt32, UInt32)? {
    var mods = 0
    var key: Int? = nil
    for part in s.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
        switch part {
        case "cmd", "command": mods |= cmdKey
        case "opt", "option", "alt": mods |= optionKey
        case "ctrl", "control": mods |= controlKey
        case "shift": mods |= shiftKey
        default: key = keyCodes[part]
        }
    }
    guard let k = key else { return nil }
    return (UInt32(k), UInt32(mods))
}

// ── Clipboard + synthetic keys ───────────────────────────────────────────────

/// Event source with its own private state, so physically held modifiers
/// (the user is still holding Cmd+Opt from the hotkey) don't leak in.
let keySource = CGEventSource(stateID: .privateState)

func pressKey(_ key: Int, flags: CGEventFlags) {
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: keySource, virtualKey: CGKeyCode(key), keyDown: down)
        e?.flags = flags
        e?.post(tap: .cghidEventTap)
    }
}

/// Wait until the user releases the hotkey's modifiers (max ~1s), so the
/// target app sees a clean Cmd+C / Cmd+V instead of Cmd+Opt+C.
func waitForModifiersReleased(_ done: @escaping () -> Void) {
    let deadline = Date().addingTimeInterval(1.0)
    func check() {
        let f = CGEventSource.flagsState(.combinedSessionState)
        let held = f.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])
        if held.isEmpty || Date() > deadline {
            done()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: check)
        }
    }
    check()
}

typealias PasteboardSnapshot = [[NSPasteboard.PasteboardType: Data]]

func snapshotPasteboard() -> PasteboardSnapshot {
    (NSPasteboard.general.pasteboardItems ?? []).map { item in
        var d: [NSPasteboard.PasteboardType: Data] = [:]
        for t in item.types { if let v = item.data(forType: t) { d[t] = v } }
        return d
    }
}

func restorePasteboard(_ snap: PasteboardSnapshot) {
    let pb = NSPasteboard.general
    pb.clearContents()
    let items: [NSPasteboardItem] = snap.map { d in
        let item = NSPasteboardItem()
        for (t, v) in d { item.setData(v, forType: t) }
        return item
    }
    if !items.isEmpty { pb.writeObjects(items) }
}

/// Copy the current selection. Polls changeCount instead of a fixed sleep.
func copySelection(_ completion: @escaping (String?) -> Void) {
    let pb = NSPasteboard.general
    let before = pb.changeCount
    pressKey(kVK_ANSI_C, flags: .maskCommand)
    let deadline = Date().addingTimeInterval(1.0)
    func check() {
        if pb.changeCount != before {
            let s = pb.string(forType: .string)
            completion((s?.isEmpty ?? true) ? nil : s)
        } else if Date() > deadline {
            completion(nil)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: check)
        }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: check)
}

func pasteText(_ text: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(text, forType: .string)
    pressKey(kVK_ANSI_V, flags: .maskCommand)
}

// ── LLM providers ────────────────────────────────────────────────────────────

enum LLMError: LocalizedError {
    case msg(String)
    var errorDescription: String? { if case .msg(let s) = self { return s }; return nil }
}

func postJSON(_ url: URL, headers: [String: String], body: [String: Any],
              completion: @escaping (Result<Any, Error>) -> Void) {
    var req = URLRequest(url: url, timeoutInterval: 60)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
    req.httpBody = try? JSONSerialization.data(withJSONObject: body)
    URLSession.shared.dataTask(with: req) { data, resp, err in
        if let err = err { return completion(.failure(err)) }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard let data = data, let obj = try? JSONSerialization.jsonObject(with: data) else {
            return completion(.failure(LLMError.msg("HTTP \(status): unreadable response")))
        }
        if status != 200 {
            let raw = String(data: data, encoding: .utf8) ?? ""
            return completion(.failure(LLMError.msg("HTTP \(status): \(raw.prefix(500))")))
        }
        completion(.success(obj))
    }.resume()
}

func askOpenAI(system: String, text: String, completion: @escaping (Result<String, Error>) -> Void) {
    let body: [String: Any] = [
        "model": cfg("openai_model"),
        "messages": [
            ["role": "system", "content": system],
            ["role": "user", "content": text],
        ],
    ]
    postJSON(URL(string: "https://api.openai.com/v1/chat/completions")!,
             headers: ["Authorization": "Bearer \(apiKey("openai"))"], body: body) { r in
        completion(r.flatMap { obj in
            let choices = (obj as? [String: Any])?["choices"] as? [[String: Any]]
            let msg = choices?.first?["message"] as? [String: Any]
            guard let content = msg?["content"] as? String else {
                return .failure(LLMError.msg("OpenAI: no content in response"))
            }
            return .success(content)
        })
    }
}

func askGemini(system: String, text: String, completion: @escaping (Result<String, Error>) -> Void) {
    let model = cfg("gemini_model")
    let body: [String: Any] = [
        "systemInstruction": ["parts": [["text": system]]],
        "contents": [["role": "user", "parts": [["text": text]]]],
    ]
    let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
    postJSON(url, headers: ["x-goog-api-key": apiKey("gemini")], body: body) { r in
        completion(r.flatMap { obj in
            let cands = (obj as? [String: Any])?["candidates"] as? [[String: Any]]
            let parts = (cands?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]
            let out = (parts ?? []).compactMap { $0["text"] as? String }.joined()
            if out.isEmpty {
                let reason = cands?.first?["finishReason"] as? String ?? "no candidates"
                return .failure(LLMError.msg("Gemini: empty response (\(reason))"))
            }
            return .success(out)
        })
    }
}

func ask(system: String, text: String, completion: @escaping (Result<String, Error>) -> Void) {
    let provider = cfg("provider")
    if apiKey(provider).isEmpty {
        return completion(.failure(LLMError.msg("no API key for \(provider) — set it in \(configPath)")))
    }
    if provider == "gemini" {
        askGemini(system: system, text: text, completion: completion)
    } else {
        askOpenAI(system: system, text: text, completion: completion)
    }
}

/// Keep surrounding whitespace of the selection (models tend to trim it).
func preserveWhitespace(original: String, result: String) -> String {
    let lead = original.prefix { $0.isWhitespace || $0.isNewline }
    let trail = String(original.reversed().prefix { $0.isWhitespace || $0.isNewline }.reversed())
    let core = result.trimmingCharacters(in: .whitespacesAndNewlines)
    return lead + core + (original.allSatisfy { $0.isWhitespace } ? "" : trail)
}

// ── Speech ───────────────────────────────────────────────────────────────────

var audioPlayer: AVAudioPlayer?
let synth = AVSpeechSynthesizer()

func systemSpeak(_ text: String) {
    let u = AVSpeechUtterance(string: text)
    if let lang = NLLanguageRecognizer.dominantLanguage(for: text) {
        u.voice = AVSpeechSynthesisVoice(language: lang.rawValue)
    }
    synth.speak(u)
}

// ── Ticking (while waiting for the LLM) ──────────────────────────────────────

/// ticking.mp3 is looked up in the .app's Resources, next to the binary (symlinks resolved),
/// then in ~/.config/text-hotkey.
let tickingPlayer: AVAudioPlayer? = {
    let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    let candidates = [
        Bundle.main.url(forResource: "ticking", withExtension: "mp3"),
        exe.deletingLastPathComponent().appendingPathComponent("ticking.mp3"),
        URL(fileURLWithPath: configDir).appendingPathComponent("ticking.mp3"),
    ].compactMap { $0 }
    guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
          let p = try? AVAudioPlayer(contentsOf: url) else {
        log("ticking.mp3 not found — no ticking sound")
        return nil
    }
    p.numberOfLoops = -1
    p.prepareToPlay()
    return p
}()

func startTicking() {
    tickingPlayer?.currentTime = 0
    tickingPlayer?.play()
}

func stopTicking() {
    tickingPlayer?.stop()
}

func stopSpeaking() {
    audioPlayer?.stop()
    audioPlayer = nil
    synth.stopSpeaking(at: .immediate)
}

func speak(_ text: String, done: @escaping (String?) -> Void) {
    stopSpeaking()
    if cfg("provider") == "openai" && !apiKey("openai").isEmpty {
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!, timeoutInterval: 60)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey("openai"))", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": "gpt-4o-mini-tts", "voice": "alloy", "input": text, "response_format": "mp3",
        ])
        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if let data = data, status == 200, let p = try? AVAudioPlayer(data: data) {
                    audioPlayer = p
                    p.play()
                    done(nil)
                } else {
                    systemSpeak(text)   // fall back to the system voice
                    done(err?.localizedDescription ?? (status != 200 ? "TTS HTTP \(status), used system voice" : nil))
                }
            }
        }.resume()
    } else {
        systemSpeak(text)
        done(nil)
    }
}

// ── App ──────────────────────────────────────────────────────────────────────

final class App: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var busy = false
    var hotKeyRefs: [EventHotKeyRef] = []
    var actionByID: [UInt32: Action] = [:]

    func applicationDidFinishLaunching(_ n: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setIcon(idle: true)
        installHotkeyHandler()
        reload()

        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        if !trusted {
            log("⚠️  Accessibility permission is required to send Cmd+C/Cmd+V. Grant it in System Settings → Privacy & Security → Accessibility (for your terminal app if you run from a terminal), then restart.")
        }
    }

    func setIcon(idle: Bool, error: Bool = false) {
        let name = error ? "exclamationmark.triangle" : (idle ? "character.bubble" : "hourglass")
        statusItem.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "text-hotkey")
    }

    func flashError(_ msg: String) {
        log("ERROR: \(msg)")
        NSSound(named: "Funk")?.play()
        setIcon(idle: true, error: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self = self, !self.busy else { return }
            self.setIcon(idle: true)
        }
    }

    // Menu
    func buildMenu() {
        let menu = NSMenu()
        let provider = cfg("provider")
        for (id, title) in [("openai", "OpenAI (\(cfg("openai_model")))"), ("gemini", "Gemini (\(cfg("gemini_model")))")] {
            let item = NSMenuItem(title: title, action: #selector(selectProvider(_:)), keyEquivalent: "")
            item.representedObject = id
            item.target = self
            item.state = provider == id ? .on : .off
            if apiKey(id).isEmpty { item.title += " — no key" }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for a in actions() where !a.hotkeys.isEmpty {
            let item = NSMenuItem(title: "\(a.name): \(a.hotkeys.joined(separator: ", "))", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Stop speaking", action: #selector(stopSpeech), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Edit config…", action: #selector(openConfig), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Reload config", action: #selector(reloadMenu), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc func selectProvider(_ sender: NSMenuItem) {
        guard let p = sender.representedObject as? String else { return }
        saveProvider(p)
        reload()
        log("provider → \(p)")
    }
    @objc func stopSpeech() { stopSpeaking() }
    @objc func openConfig() { NSWorkspace.shared.open(URL(fileURLWithPath: configPath)) }
    @objc func reloadMenu() { reload() }

    // Hotkeys
    func installHotkeyHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            var hk = EventHotKeyID()
            GetEventParameter(event!, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let app = Unmanaged<App>.fromOpaque(userData!).takeUnretainedValue()
            if let a = app.actionByID[hk.id] {
                DispatchQueue.main.async { app.run(a) }
            }
            return noErr
        }, 1, &spec, selfPtr, nil)
    }

    func reload() {
        loadConfig()
        for r in hotKeyRefs { UnregisterEventHotKey(r) }
        hotKeyRefs = []
        actionByID = [:]
        var nextID: UInt32 = 1
        for a in actions() {
            for hk in a.hotkeys {
                guard let (code, mods) = parseHotkey(hk) else { log("bad hotkey '\(hk)' for \(a.name)"); continue }
                var ref: EventHotKeyRef?
                let st = RegisterEventHotKey(code, mods, EventHotKeyID(signature: OSType(0x54584854), id: nextID),
                                             GetApplicationEventTarget(), 0, &ref)
                if st == noErr, let ref = ref {
                    hotKeyRefs.append(ref)
                    actionByID[nextID] = a
                    log("\(a.name): \(hk)")
                } else {
                    log("could not register \(hk) for \(a.name) (taken by another app?) status=\(st)")
                }
                nextID += 1
            }
        }
        buildMenu()
    }

    // Action pipeline: wait for modifiers → Cmd+C → LLM → Cmd+V → restore clipboard
    func run(_ a: Action) {
        if a.name == "speak", audioPlayer?.isPlaying == true || synth.isSpeaking {
            stopSpeaking()          // same hotkey toggles speech off
            return
        }
        guard !busy else { log("busy, ignoring \(a.name)"); return }
        busy = true
        setIcon(idle: false)
        let snapshot = snapshotPasteboard()
        let restore = (config["restore_clipboard"] as? Bool) ?? true

        func finish(_ err: String?) {
            busy = false
            if let e = err { flashError(e) } else { setIcon(idle: true) }
        }

        waitForModifiersReleased {
            copySelection { text in
                guard let text = text else {
                    if restore { restorePasteboard(snapshot) }
                    return finish("no text selected (or Accessibility permission missing)")
                }
                log("\(a.name): \(text.count) chars via \(cfg("provider"))")

                if a.name == "speak" {
                    if restore { restorePasteboard(snapshot) }
                    return speak(text) { finish($0) }
                }

                startTicking()
                ask(system: a.prompt, text: text) { result in
                    DispatchQueue.main.async {
                        stopTicking()
                        switch result {
                        case .failure(let e):
                            if restore { restorePasteboard(snapshot) }
                            finish(e.localizedDescription)
                        case .success(let out):
                            let final = preserveWhitespace(original: text, result: out)
                            waitForModifiersReleased {
                                pasteText(final)
                                // give the target app time to read the pasteboard before restoring
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                    if restore { restorePasteboard(snapshot) }
                                    finish(nil)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
log("text-hotkey started; config: \(configPath)")
app.run()
