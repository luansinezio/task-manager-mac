// App de barra de menu do Task Manager: clicou no ícone, abre o painel compacto (o mesmo da mesa).
// Encostou o mouse no canto superior direito da tela, a lista abre no centro. Esc ou clique fora fecha.
// Build e instalação: ./instalar.sh
import Cocoa
import WebKit

let BASE = "http://localhost:8790"

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

    func applicationDidFinishLaunching(_ n: Notification) {
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
        Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in self?.vigiarCanto() }

        contar()
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.contar() }
    }

    func carregar() {
        falhou = false
        web.load(URLRequest(url: URL(string: BASE + "/?widget")!))
        webCentro?.load(URLRequest(url: URL(string: BASE + "/?widget&largo&moldura")!))
    }

    // ---- painel central, aberto pelo canto da tela ----
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

    // ---- altura: a página avisa o tamanho da lista e a janela acompanha ----
    var alturaCentro: CGFloat = 680
    var alturaPopover: CGFloat = 660

    func config() -> WKWebViewConfiguration {
        let c = WKWebViewConfiguration()
        c.userContentController.add(self, name: "altura")
        return c
    }

    func userContentController(_ u: WKUserContentController, didReceive m: WKScriptMessage) {
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

    func abrirCentro() {
        let p = NSEvent.mouseLocation
        let tela = NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main!
        let v = tela.visibleFrame
        let h = min(alturaCentro, v.height - 80), w = min(860, v.width - 80)
        painel.setFrame(NSRect(x: v.midX - w / 2, y: v.midY - h / 2, width: w, height: h), display: true)
        webCentro.evaluateJavaScript("puxar()")
        painel.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        painel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { c in c.duration = 0.16; painel.animator().alphaValue = 1 }
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
            if let d, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let dados = j["dados"] as? [String: Any], let secoes = dados["secoes"] as? [String: [String: Any]] {
                var n = 0
                for s in secoes.values where (s["tipo"] as? String) == "check" {
                    for it in (s["itens"] as? [[String: Any]]) ?? [] where (it["feito"] as? Bool) != true { n += 1 }
                }
                titulo = " \(n)"
            }
            DispatchQueue.main.async { self.item.button?.title = titulo }
        }.resume()
    }
}

let app = NSApplication.shared
let delegado = App()
app.delegate = delegado
app.setActivationPolicy(.accessory)
app.run()
