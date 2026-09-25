// App Tarefas: o Task Manager fora do navegador.
// Barra de menu: clicou no ícone, abre o painel compacto (o mesmo da mesa).
// Canto superior direito da tela: a lista abre no centro, larga. Esc ou clique fora fecha.
// Dock (opcional, nos ajustes): clicar no ícone abre a lista no centro.
// A engrenagem no topo do painel abre os ajustes; a página conversa com o app pela ponte "ajustes".
// Build e instalação: ./instalar.sh
import Cocoa
import ServiceManagement
import WebKit

let BASE = "http://localhost:8790"
let WIDGET_ID = "task-manager-jsx"
let UBERSICHT = "tracesOf.Uebersicht"

final class Painel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

final class App: NSObject, NSApplicationDelegate, WKNavigationDelegate, NSWindowDelegate, WKScriptMessageHandler {
    var item: NSStatusItem!
    var painel: Painel!
    var webCentro: WKWebView!
    var noCanto = false
    var entrouNoCanto: Date?
    let popover = NSPopover()
    var web: WKWebView!
    var falhou = false
    let prefs = UserDefaults.standard

    // ---- ajustes guardados ----
    var modo: String { prefs.string(forKey: "modo") ?? "menu" }         // menu · dock · ambos
    var cantoLigado: Bool { prefs.object(forKey: "canto") as? Bool ?? true }

    func applicationDidFinishLaunching(_ n: Notification) {
        // uma instância só
        let outros = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        if outros.count > 1 { NSApp.terminate(nil); return }

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = item.button {
            b.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Tarefas")
            b.imagePosition = .imageLeading
            b.target = self
            b.action = #selector(clique(_:))
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 380, height: 660), configuration: config())
        web.navigationDelegate = self
        web.setValue(false, forKey: "drawsBackground")
        let vc = NSViewController()
        vc.view = web
        popover.contentViewController = vc
        popover.contentSize = NSSize(width: 380, height: 660)
        popover.behavior = .transient
        carregar()

        montarPainel()
        montarMenuPrincipal()
        aplicarModo()

        // primeira execução: liga o abrir no login
        if prefs.object(forKey: "loginConfigurado") == nil {
            try? SMAppService.mainApp.register()
            prefs.set(true, forKey: "loginConfigurado")
        }

        Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in self?.vigiarCanto() }
        contar()
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.contar() }
    }

    func carregar() {
        falhou = false
        web.load(URLRequest(url: URL(string: BASE + "/?widget")!))
        webCentro?.load(URLRequest(url: URL(string: BASE + "/?widget&largo&moldura")!))
    }

    // ---- modo: barra de menu, Dock ou os dois ----
    func aplicarModo() {
        item.isVisible = modo != "dock"
        NSApp.setActivationPolicy(modo == "menu" ? .accessory : .regular)
    }

    // Clique no ícone do Dock
    func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows v: Bool) -> Bool {
        painel.isVisible ? fecharCentro() : abrirCentro(naTelaDoMouse: false)
        return false
    }

    func montarMenuPrincipal() {
        let principal = NSMenu()
        let appItem = NSMenuItem()
        principal.addItem(appItem)
        let m = NSMenu()
        m.addItem(withTitle: "Ajustes…", action: #selector(abrirAjustes), keyEquivalent: ",").target = self
        m.addItem(withTitle: "Abrir no navegador", action: #selector(abrir), keyEquivalent: "").target = self
        m.addItem(.separator())
        m.addItem(withTitle: "Sair do Tarefas", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = m
        NSApp.mainMenu = principal
    }

    // ---- painel central, aberto pelo canto da tela ou pelo Dock ----
    func montarPainel() {
        painel = Painel(contentRect: NSRect(x: 0, y: 0, width: 860, height: 680),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        painel.level = .floating
        painel.isOpaque = false
        painel.backgroundColor = .clear
        painel.hasShadow = true
        painel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        painel.delegate = self
        webCentro = WKWebView(frame: painel.contentRect(forFrameRect: painel.frame), configuration: config())
        webCentro.setValue(false, forKey: "drawsBackground")
        webCentro.wantsLayer = true
        webCentro.layer?.cornerRadius = 16
        webCentro.layer?.masksToBounds = true
        painel.contentView = webCentro
        webCentro.load(URLRequest(url: URL(string: BASE + "/?widget&largo&moldura")!))
    }

    func vigiarCanto() {
        guard cantoLigado else { return }
        let p = NSEvent.mouseLocation
        let dentro = NSScreen.screens.contains { t in
            let f = t.frame
            return p.x >= f.maxX - 3 && p.y >= f.maxY - 3 && p.x <= f.maxX && p.y <= f.maxY
        }
        if !dentro { noCanto = false; entrouNoCanto = nil; return }
        if noCanto { return }
        if entrouNoCanto == nil { entrouNoCanto = Date(); return }
        if Date().timeIntervalSince(entrouNoCanto!) < 0.12 { return }
        noCanto = true
        painel.isVisible ? fecharCentro() : abrirCentro()
    }

    // ---- ponte com a página: altura e ajustes ----
    var alturaCentro: CGFloat = 680
    var alturaPopover: CGFloat = 660

    func config() -> WKWebViewConfiguration {
        let c = WKWebViewConfiguration()
        c.userContentController.add(self, name: "altura")
        c.userContentController.add(self, name: "ajustes")
        return c
    }

    func userContentController(_ u: WKUserContentController, didReceive m: WKScriptMessage) {
        if m.name == "ajustes", let corpo = m.body as? [String: Any] { return ajustes(corpo) }
        guard let n = m.body as? NSNumber else { return }
        let h = CGFloat(truncating: n)
        if m.webView === webCentro {
            alturaCentro = h
            if painel.isVisible {
                // cresce e encolhe pra baixo: o topo fica parado enquanto a lista muda
                let v = (painel.screen ?? NSScreen.main!).visibleFrame
                var f = painel.frame
                let nova = min(h, v.height - 80)
                f.origin.y = max(v.minY + 40, f.maxY - nova)
                f.size.height = nova
                painel.setFrame(f, display: true, animate: false)
            }
        } else {
            alturaPopover = min(h, 720)
            popover.contentSize = NSSize(width: 380, height: alturaPopover)
        }
    }

    func ajustes(_ corpo: [String: Any]) {
        switch corpo["acao"] as? String {
        case "definir":
            let valor = corpo["valor"]
            switch corpo["chave"] as? String {
            case "modo":
                if let v = valor as? String {
                    prefs.set(v, forKey: "modo")
                    aplicarModo()
                    // saiu da barra de menu com o popover aberto: continua nos ajustes, agora no centro
                    if v == "dock" && popover.isShown { popover.performClose(nil); abrirAjustes() }
                }
            case "canto": prefs.set(valor as? Bool ?? true, forKey: "canto")
            case "login":
                if valor as? Bool == true { try? SMAppService.mainApp.register() }
                else { try? SMAppService.mainApp.unregister() }
            case "widget": definirWidget(valor as? Bool ?? false)
            default: break
            }
            enviarAjustes()
        case "navegador": abrir()
        case "sair": NSApp.terminate(nil)
        default: enviarAjustes()
        }
    }

    func enviarAjustes() {
        let (disponivel, ligado) = estadoWidget()
        let estado: [String: Any] = [
            "modo": modo, "canto": cantoLigado,
            "login": SMAppService.mainApp.status == .enabled,
            "widget": ligado, "widgetDisponivel": disponivel,
        ]
        guard let d = try? JSONSerialization.data(withJSONObject: estado), let j = String(data: d, encoding: .utf8) else { return }
        for w in [web, webCentro] { w?.evaluateJavaScript("window.receberAjustes && receberAjustes(\(j))") }
    }

    // ---- widget da mesa, pelo AppleScript do Übersicht ----
    var arquivoWidget: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Übersicht/widgets/task-manager.jsx")
    }

    func estadoWidget() -> (disponivel: Bool, ligado: Bool) {
        let instalado = NSWorkspace.shared.urlForApplication(withBundleIdentifier: UBERSICHT) != nil
        guard instalado, FileManager.default.fileExists(atPath: arquivoWidget.path) else { return (false, false) }
        let rodando = !NSRunningApplication.runningApplications(withBundleIdentifier: UBERSICHT).isEmpty
        guard rodando else { return (true, false) }
        let r = rodarScript("tell application id \"\(UBERSICHT)\" to get hidden of widget id \"\(WIDGET_ID)\"")
        return (true, r?.booleanValue == false)
    }

    func definirWidget(_ ligar: Bool) {
        if ligar, NSRunningApplication.runningApplications(withBundleIdentifier: UBERSICHT).isEmpty,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: UBERSICHT) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            Thread.sleep(forTimeInterval: 1.5)
        }
        _ = rodarScript("tell application id \"\(UBERSICHT)\" to set hidden of widget id \"\(WIDGET_ID)\" to \(!ligar)")
    }

    func rodarScript(_ fonte: String) -> NSAppleEventDescriptor? {
        var erro: NSDictionary?
        return NSAppleScript(source: fonte)?.executeAndReturnError(&erro)
    }

    // ---- abrir e fechar ----
    func abrirCentro(naTelaDoMouse: Bool = true) {
        let p = NSEvent.mouseLocation
        let tela = naTelaDoMouse ? (NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main!) : NSScreen.main!
        let v = tela.visibleFrame
        let h = min(alturaCentro, v.height - 80), w = min(860, v.width - 80)
        painel.setFrame(NSRect(x: v.midX - w / 2, y: v.midY - h / 2, width: w, height: h), display: true)
        webCentro.evaluateJavaScript("puxar()")
        painel.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        painel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { c in c.duration = 0.16; painel.animator().alphaValue = 1 }
    }

    @objc func abrirAjustes() {
        if !painel.isVisible { abrirCentro(naTelaDoMouse: false) }
        webCentro.evaluateJavaScript("mostrarAjustes()")
    }

    func fecharCentro() { painel.orderOut(nil) }
    func windowDidResignKey(_ n: Notification) { fecharCentro() }

    func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) { falhou = true }
    func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) { falhou = true }

    @objc func clique(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp { return menu() }
        if popover.isShown { popover.performClose(sender); return }
        fecharCentro()
        if falhou { carregar() } else { web.evaluateJavaScript("puxar()") }
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    func menu() {
        let m = NSMenu()
        m.addItem(withTitle: "Ajustes…", action: #selector(abrirAjustes), keyEquivalent: "").target = self
        m.addItem(withTitle: "Abrir no navegador", action: #selector(abrir), keyEquivalent: "").target = self
        m.addItem(withTitle: "Recarregar", action: #selector(recarregar), keyEquivalent: "").target = self
        m.addItem(.separator())
        m.addItem(withTitle: "Sair", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = m
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc func abrir() { NSWorkspace.shared.open(URL(string: BASE)!) }
    @objc func recarregar() { carregar(); contar() }

    func contar() {
        URLSession.shared.dataTask(with: URL(string: BASE + "/api/tarefas")!) { d, _, _ in
            var titulo = ""
            var n = 0
            if let d, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let dados = j["dados"] as? [String: Any], let secoes = dados["secoes"] as? [String: [String: Any]] {
                for s in secoes.values where (s["tipo"] as? String) == "check" {
                    for it in (s["itens"] as? [[String: Any]]) ?? [] where (it["feito"] as? Bool) != true { n += 1 }
                }
                titulo = " \(n)"
            }
            DispatchQueue.main.async {
                self.item.button?.title = titulo
                NSApp.dockTile.badgeLabel = n > 0 ? "\(n)" : nil
            }
        }.resume()
    }
}

let app = NSApplication.shared
let delegado = App()
app.delegate = delegado
app.setActivationPolicy(.accessory)
app.run()
