// App Tarefas: o Task Manager fora do navegador.
// Barra de menu: clicou no ícone, abre o painel compacto (o mesmo da mesa).
// Canto superior direito da tela: a lista abre no centro, larga. Esc ou clique fora fecha.
// Dock (opcional, nos ajustes): o app vira uma janela normal, que arrasta, redimensiona e lembra a posição.
// A engrenagem no topo do painel abre os ajustes; a página conversa com o app pela ponte "ajustes".
// Build e instalação: ./instalar.sh
import Cocoa
import ServiceManagement
import UserNotifications
import WebKit

let BASE = "http://localhost:8790"
let WIDGET_ID = "task-manager-jsx"
let UBERSICHT = "tracesOf.Uebersicht"

// Faixa invisível no topo da janela: como a página ocupa a janela inteira, é por aqui que se arrasta.
final class Arrasto: NSView {
    override func mouseDown(with e: NSEvent) {
        if e.clickCount == 2 { window?.performZoom(nil) } else { window?.performDrag(with: e) }
    }
}

final class Painel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

final class App: NSObject, NSApplicationDelegate, WKNavigationDelegate, NSWindowDelegate, WKScriptMessageHandler, UNUserNotificationCenterDelegate {
    var item: NSStatusItem!
    var painel: Painel!
    var webCentro: WKWebView!
    var noCanto = false
    var entrouNoCanto: Date?
    let popover = NSPopover()
    var web: WKWebView!
    var janela: NSWindow!
    var webJanela: WKWebView!
    var falhou = false
    let prefs = UserDefaults.standard

    // ---- ajustes guardados ----
    var modo: String { prefs.string(forKey: "modo") ?? "menu" }         // menu · dock · ambos
    var cantoLigado: Bool { prefs.object(forKey: "canto") as? Bool ?? true }
    var avisosLigados: Bool { prefs.object(forKey: "avisos") as? Bool ?? true }

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
        montarJanela()
        montarMenuPrincipal()
        aplicarModo()

        // primeira execução: liga o abrir no login
        if prefs.object(forKey: "loginConfigurado") == nil {
            try? SMAppService.mainApp.register()
            prefs.set(true, forKey: "loginConfigurado")
        }

        Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in self?.vigiarCanto() }
        contar()
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.contar() }
        prepararAvisos()
    }

    func carregar() {
        falhou = false
        web.load(URLRequest(url: URL(string: BASE + "/?widget")!))
        webCentro?.load(URLRequest(url: URL(string: BASE + "/?widget&largo&moldura")!))
        webJanela?.load(URLRequest(url: URL(string: BASE + "/?app")!))
    }

    // ---- janela normal (modo Dock) ----
    func montarJanela() {
        janela = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 720),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        janela.title = "Tarefas"
        janela.titleVisibility = .hidden
        janela.titlebarAppearsTransparent = true
        janela.isReleasedWhenClosed = false
        janela.minSize = NSSize(width: 380, height: 420)
        janela.tabbingMode = .disallowed
        // barra de título alta (sem itens): desce os botões e dá margem em cima; a página alinha o eyebrow com eles
        janela.toolbar = NSToolbar(identifier: "tarefas")
        janela.toolbarStyle = .unified
        // mesma cor do fundo da página, pra barra de título sumir nela
        janela.backgroundColor = NSColor(name: nil) { a in
            a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 0x0E / 255, alpha: 1) : NSColor(white: 0xEA / 255, alpha: 1)
        }
        let base = NSView(frame: NSRect(x: 0, y: 0, width: 980, height: 720))
        webJanela = WKWebView(frame: base.bounds, configuration: config())
        webJanela.setValue(false, forKey: "drawsBackground")
        webJanela.autoresizingMask = [.width, .height]
        base.addSubview(webJanela)
        let faixa = Arrasto(frame: NSRect(x: 0, y: base.bounds.height - 16, width: base.bounds.width, height: 16))
        faixa.autoresizingMask = [.width, .minYMargin]
        base.addSubview(faixa)
        janela.contentView = base
        webJanela.load(URLRequest(url: URL(string: BASE + "/?app")!))
        janela.center()
        janela.setFrameAutosaveName("JanelaTarefas")
    }

    @objc func mostrarJanela() {
        fecharCentro()
        if popover.isShown { popover.performClose(nil) }
        webJanela.evaluateJavaScript("puxar()")
        NSApp.activate(ignoringOtherApps: true)
        janela.makeKeyAndOrderFront(nil)
    }

    // ---- modo: barra de menu, Dock ou os dois ----
    func aplicarModo() {
        item.isVisible = modo != "dock"
        NSApp.setActivationPolicy(modo == "menu" ? .accessory : .regular)
    }

    // Clique no ícone do Dock
    func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows v: Bool) -> Bool {
        mostrarJanela()
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

        let editar = NSMenu(title: "Editar")
        editar.addItem(withTitle: "Desfazer", action: Selector(("undo:")), keyEquivalent: "z")
        editar.addItem(withTitle: "Refazer", action: Selector(("redo:")), keyEquivalent: "Z")
        editar.addItem(.separator())
        editar.addItem(withTitle: "Recortar", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editar.addItem(withTitle: "Copiar", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editar.addItem(withTitle: "Colar", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editar.addItem(withTitle: "Selecionar tudo", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editarItem = NSMenuItem(); editarItem.submenu = editar; principal.addItem(editarItem)

        let jan = NSMenu(title: "Janela")
        jan.addItem(withTitle: "Mostrar a lista", action: #selector(mostrarJanela), keyEquivalent: "0").target = self
        jan.addItem(withTitle: "Minimizar", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        jan.addItem(withTitle: "Fechar", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let janItem = NSMenuItem(); janItem.submenu = jan; principal.addItem(janItem)
        NSApp.windowsMenu = jan

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
        guard let n = m.body as? NSNumber, m.webView !== webJanela else { return }
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
                    if v != "menu" { mostrarJanela() }
                }
            case "canto": prefs.set(valor as? Bool ?? true, forKey: "canto")
            case "avisos":
                prefs.set(valor as? Bool ?? true, forKey: "avisos")
                if valor as? Bool == true { prepararAvisos() }
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
            "modo": modo, "canto": cantoLigado, "avisos": avisosLigados,
            "login": SMAppService.mainApp.status == .enabled,
            "widget": ligado, "widgetDisponivel": disponivel,
        ]
        guard let d = try? JSONSerialization.data(withJSONObject: estado), let j = String(data: d, encoding: .utf8) else { return }
        for w in [web, webCentro, webJanela] { w?.evaluateJavaScript("window.receberAjustes && receberAjustes(\(j))") }
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
        if modo != "menu" { mostrarJanela(); webJanela.evaluateJavaScript("mostrarAjustes()"); return }
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
        m.addItem(withTitle: "Abrir em janela", action: #selector(mostrarJanela), keyEquivalent: "").target = self
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

    // ---- barra de menu: rodando, aprovar, responder, destravar ----
    // Tudo zerado: ícone de lista e o número de abertas. Com algo acontecendo: um ícone e um número por tipo.
    var estadosVistos: [String: String]? = nil

    func contar() {
        URLSession.shared.dataTask(with: URL(string: BASE + "/api/tarefas")!) { d, _, _ in
            guard let d, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let dados = j["dados"] as? [String: Any], let secoes = dados["secoes"] as? [String: [String: Any]] else {
                DispatchQueue.main.async { self.pintarBarra(abertas: nil, tipos: [:]) }
                return
            }
            var abertas = 0
            var tipos: [String: Int] = [:]
            var pendentes: [[String: Any]] = []
            let agora = Date()
            let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            for s in secoes.values where (s["tipo"] as? String) == "check" {
                for it in (s["itens"] as? [[String: Any]]) ?? [] where (it["feito"] as? Bool) != true {
                    abertas += 1
                    guard let ia = it["ia"] as? [String: Any], let est = ia["estado"] as? String else { continue }
                    switch est {
                    case "fazendo":
                        let quando = fmt.date(from: (ia["atualizado"] as? String) ?? (ia["inicio"] as? String) ?? "")
                        if let q = quando, agora.timeIntervalSince(q) > 30 * 60 { continue }   // parada não conta como rodando
                        tipos["rodando", default: 0] += 1
                    case "revisar": tipos["aprovar", default: 0] += 1; pendentes.append(it)
                    case "aguardando": tipos["responder", default: 0] += 1; pendentes.append(it)
                    case "devolvida": tipos["destravar", default: 0] += 1; pendentes.append(it)
                    default: break
                    }
                }
            }
            DispatchQueue.main.async {
                self.pintarBarra(abertas: abertas, tipos: tipos)
                self.avisarNovidades(pendentes)
            }
        }.resume()
    }

    static let simbolos: [(String, String)] = [("rodando", "sparkle"), ("aprovar", "checkmark.seal"),
                                                ("responder", "questionmark.bubble"), ("destravar", "exclamationmark.triangle")]

    func pintarBarra(abertas: Int?, tipos: [String: Int]) {
        guard let b = item.button else { return }
        let pendencias = (tipos["aprovar"] ?? 0) + (tipos["responder"] ?? 0) + (tipos["destravar"] ?? 0)
        NSApp.dockTile.badgeLabel = pendencias > 0 ? "\(pendencias)" : nil
        let partes = App.simbolos.compactMap { (chave, sim) -> (String, Int)? in
            let n = tipos[chave] ?? 0
            return n > 0 ? (sim, n) : nil
        }
        if partes.isEmpty {
            b.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Tarefas")
            b.title = abertas.map { " \($0)" } ?? ""
            b.toolTip = abertas.map { "\($0) tarefas abertas" }
            return
        }
        b.title = ""
        b.image = imagemBarra(partes)
        let nomes = ["rodando": "rodando", "aprovar": "pra aprovar", "responder": "pra responder", "destravar": "pra destravar"]
        b.toolTip = App.simbolos.compactMap { (k, _) in (tipos[k] ?? 0) > 0 ? "\(tipos[k]!) \(nomes[k]!)" : nil }.joined(separator: " · ")
    }

    // Desenha os ícones e números numa imagem-modelo: o macOS pinta na cor certa da barra (claro ou escuro).
    func imagemBarra(_ partes: [(String, Int)]) -> NSImage {
        let fonte = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: fonte, .foregroundColor: NSColor.black]
        let altura: CGFloat = 18, gapIcone: CGFloat = 3, gapParte: CGFloat = 9
        var pecas: [(NSImage, NSAttributedString)] = []
        var largura: CGFloat = 0
        for (sim, n) in partes {
            let img = NSImage(systemSymbolName: sim, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) ?? NSImage()
            let txt = NSAttributedString(string: "\(n)", attributes: attrs)
            pecas.append((img, txt))
            largura += img.size.width + gapIcone + txt.size().width
        }
        largura += gapParte * CGFloat(max(0, pecas.count - 1))
        let imagem = NSImage(size: NSSize(width: ceil(largura), height: altura), flipped: false) { _ in
            var x: CGFloat = 0
            for (img, txt) in pecas {
                let t = img.size
                img.draw(in: NSRect(x: x, y: (altura - t.height) / 2, width: t.width, height: t.height))
                x += t.width + gapIcone
                let ts = txt.size()
                txt.draw(at: NSPoint(x: x, y: (altura - ts.height) / 2))
                x += ts.width + gapParte
            }
            return true
        }
        imagem.isTemplate = true
        return imagem
    }

    // ---- avisos do macOS: um modelo por tipo ----
    func prepararAvisos() {
        let c = UNUserNotificationCenter.current()
        c.delegate = self
        let aprovar = UNNotificationCategory(identifier: "aprovar", actions: [
            UNNotificationAction(identifier: "aprovar", title: "Aprovar", options: []),
            UNNotificationAction(identifier: "ver", title: "Ver", options: [.foreground]),
        ], intentIdentifiers: [])
        let responder = UNNotificationCategory(identifier: "responder", actions: [
            UNTextInputNotificationAction(identifier: "responder", title: "Responder", options: [],
                                          textInputButtonTitle: "Enviar", textInputPlaceholder: "Sua resposta"),
        ], intentIdentifiers: [])
        let destravar = UNNotificationCategory(identifier: "destravar", actions: [
            UNNotificationAction(identifier: "ver", title: "Ver", options: [.foreground]),
        ], intentIdentifiers: [])
        c.setNotificationCategories([aprovar, responder, destravar])
        c.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func avisarNovidades(_ pendentes: [[String: Any]]) {
        var atuais: [String: String] = [:]
        for it in pendentes {
            if let id = it["id"] as? String, let est = (it["ia"] as? [String: Any])?["estado"] as? String { atuais[id] = est }
        }
        defer { estadosVistos = atuais }
        guard let vistos = estadosVistos, avisosLigados else { return }   // primeira leitura só registra
        for it in pendentes {
            guard let id = it["id"] as? String, let ia = it["ia"] as? [String: Any],
                  let est = ia["estado"] as? String, vistos[id] != est else { continue }
            let texto = (it["texto"] as? String) ?? ""
            let quem = nomeAgente(ia["agente"] as? String)
            let conteudo = UNMutableNotificationContent()
            conteudo.userInfo = ["id": id]
            conteudo.sound = .default
            switch est {
            case "revisar":
                conteudo.categoryIdentifier = "aprovar"
                conteudo.title = "Pra aprovar · \(quem)"
                conteudo.body = "\(texto): \((ia["nota"] as? String) ?? "pronto pra revisar")"
            case "aguardando":
                conteudo.categoryIdentifier = "responder"
                conteudo.title = "\(quem) precisa de você"
                let etapa = (ia["etapa"] as? String).map { " (etapa \($0))" } ?? ""
                conteudo.body = "\(texto)\(etapa): \((ia["pergunta"] as? String) ?? "")"
            default:
                conteudo.categoryIdentifier = "destravar"
                conteudo.title = "\(quem) devolveu"
                conteudo.body = "\(texto): falta \((ia["nota"] as? String) ?? "algo seu")"
            }
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "\(id)-\(est)", content: conteudo, trigger: nil))
        }
    }

    func nomeAgente(_ a: String?) -> String {
        switch a ?? "" {
        case "claude": return "Claude"
        case "codex": return "Codex"
        case "chatgpt": return "ChatGPT"
        case "gemini": return "Gemini"
        case "", "ia": return "IA"
        default: return a!.prefix(1).uppercased() + a!.dropFirst()
        }
    }

    // aviso aparece mesmo com o app na frente
    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                                withCompletionHandler fim: @escaping (UNNotificationPresentationOptions) -> Void) {
        fim([.banner, .sound])
    }

    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse,
                                withCompletionHandler fim: @escaping () -> Void) {
        let id = r.notification.request.content.userInfo["id"] as? String ?? ""
        switch r.actionIdentifier {
        case "aprovar": enviarOp(["op": "toggle", "id": id])
        case "responder":
            if let t = (r as? UNTextInputNotificationResponse)?.userText, !t.isEmpty {
                enviarOp(["op": "responder", "id": id, "resposta": t])
            }
        default:
            DispatchQueue.main.async { self.modo == "menu" ? self.abrirCentro(naTelaDoMouse: false) : self.mostrarJanela() }
        }
        fim()
    }

    func enviarOp(_ corpo: [String: Any]) {
        var req = URLRequest(url: URL(string: BASE + "/api/op")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: corpo)
        URLSession.shared.dataTask(with: req) { _, _, _ in DispatchQueue.main.async { self.contar() } }.resume()
    }
}

let app = NSApplication.shared
let delegado = App()
app.delegate = delegado
app.setActivationPolicy(.accessory)
app.run()
