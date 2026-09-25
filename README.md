# Task Manager

Lista de tarefas pessoal pro macOS, que roda 100% local e aparece em três lugares ao mesmo tempo:

- **No navegador**, em `http://localhost:8790`
- **Na barra de menu**, com o número de tarefas abertas; clicou, abre a lista num painel
- **No canto da tela**: encostou o mouse no canto superior direito, a lista abre no centro, larga e em duas colunas
- **Numa janela própria** (opcional), com ícone no Dock: arrasta, redimensiona e lembra onde ficou
- **Na mesa** (opcional), como widget fixo na área de trabalho

Tudo lê o mesmo arquivo, então marcar num lugar atualiza os outros em segundos. Segue o tema do sistema (claro ou escuro) sozinho.

![Painel do canto, tema escuro](docs/canto-escuro.png)

| Claro | Widget da mesa |
|---|---|
| ![Painel do canto, tema claro](docs/canto-claro.png) | ![Widget da mesa](docs/mesa-escuro.png) |

## O que precisa

- macOS 13 ou mais novo
- Ferramentas de linha de comando da Apple (trazem `python3` e `swiftc`). Se não tiver:

```bash
xcode-select --install
```

- Opcional, só pro widget da mesa: [Übersicht](https://tracesof.net/uebersicht/)

```bash
brew install --cask ubersicht
```

Não tem dependência de Python nem de Node. O servidor usa só a biblioteca padrão.

## Instalar

```bash
git clone https://github.com/luansinezio/task-manager-mac.git
cd task-manager-mac
./instalar.sh
```

O instalador:

1. Registra o servidor como serviço do macOS: sobe no login e reinicia se cair.
2. Compila o app **Tarefas** (barra de menu, canto da tela e, se quiser, Dock) em `~/Applications/Tarefas.app`. Na primeira vez ele se registra pra abrir no login.
3. Desliga o Canto Ativo do macOS no canto superior direito, pra não abrir duas coisas ao mesmo tempo.
4. Se o Übersicht estiver instalado, liga o widget da mesa.
5. Conecta o copiloto de IA (MCP) no Claude Code, Claude Desktop, Codex e Gemini CLI, os que estiverem instalados.

Na primeira vez que você ligar ou desligar o widget pelos ajustes, o macOS pergunta se o Tarefas pode controlar o Übersicht. É só permitir.

Na primeira vez a lista começa com tarefas de exemplo. Suas tarefas ficam em `dados/tarefas.json`, que não vai pro git.

## Usar

| Onde | Como |
|---|---|
| Marcar como feita | Clique no quadrado |
| Editar | Clique no texto; Enter salva, Esc cancela; apagar o texto apaga a tarefa |
| Adicionar | "+ Adicionar" no fim de cada seção |
| Mudar de seção | Arraste pela alça à esquerda da tarefa (na página) |
| Limpar o dia | Botão "Limpar feitas" tira tudo o que já foi marcado |
| Canto da tela | Mouse no canto superior direito abre; Esc, clique fora ou o canto de novo fecha |
| Barra de menu | Clique abre o painel; botão direito tem Ajustes, Abrir no navegador, Recarregar e Sair |
| Janela | Nos ajustes, escolha Dock ou Os dois: clicar no ícone do Dock abre a lista numa janela normal, compacta, que vira duas colunas quando larga (⌘W fecha, ⌘M minimiza) |
| Ajustes | Engrenagem no topo do painel: onde o app aparece (barra de menu, Dock ou os dois), widget da mesa ligado ou não, atalho do canto, abrir ao ligar o Mac |
| Tema | Segue o sistema. Na página dá pra forçar claro ou escuro no botão de tema |

### Pelo terminal

Útil pra scripts e pra agentes de IA (Claude Code, Codex) mexerem na lista:

```bash
python3 tm.py lista
python3 tm.py add rapidas "Responder o fulano"
python3 tm.py check t04            # alterna feito/aberto
python3 tm.py edit t04 "Texto novo"
python3 tm.py move t04 amanha
python3 tm.py rm t04
python3 tm.py limpar               # tira as feitas
```

Seções: `rapidas`, `demoradas`, `particular`, `semana`, `amanha`, `anotacoes`. A tela pega a mudança em até 2 segundos.

## Copiloto de IA

A lista é compartilhada com a sua IA. Cada tarefa pode ser **sua** ou **da IA**, e a tela mostra ao vivo quem está fazendo o quê: o logo da IA (Claude, Codex, Gemini), uma barra de progresso e uma nota curta do passo atual.

Como funciona:

1. Você despeja as tarefas na conversa com a IA (ou só abre a conversa).
2. A IA faz a triagem: o que ela resolve sozinha (escrever, pesquisar, rascunhar, codar, organizar) fica com ela; o que depende de você (ligar, assinar, pagar, decidir, fazer login) fica com você.
3. Quando você autoriza, ela pega a tarefa, vai atualizando a barra e conclui. Tarefa que ela resolve de ponta a ponta sai marcada como feita.
4. **A IA prepara, você dispara.** O que sai pra fora e não desfaz (email, mensagem, publicação, pagamento) fica em **Revisar** até você conferir e marcar.
5. Se ela travar, devolve a tarefa pra você dizendo o que falta.

Na tela, a faísca ao lado de cada tarefa passa ela pra IA ou pega de volta.

### Precisa de você

Quando alguma IA precisa de você, isso aparece em três lugares:

- **Barra de menu:** um ícone e um número por tipo: ✦ rodando, ✓ aprovar, 💬 responder, ⚠ destravar. Sem nada acontecendo, volta ao número de abertas.
- **Topo do painel:** o bloco "Precisa de você", com uma placa por pendência.
  - **Aprovar:** o resultado pronto (texto ou arquivo), com Aprovar, Copiar e Devolver à IA com comentário.
  - **Responder:** a pergunta da IA e a etapa em que ela parou, com um campo pra responder. A resposta volta direto pra IA, que continua sozinha.
  - **Destravar:** o que falta, com "Resolvi, devolver à IA" e "Fica comigo".
- **Aviso do macOS:** um modelo por tipo. No de Responder dá pra responder direto na notificação. Liga e desliga nos ajustes.

### Barra de status de toda sessão

A lista não é só pro que você passa pra IA: ela mostra tudo que as IAs estão fazendo, no nível macro.

- Toda sessão do Claude Code começa com um resumo da lista (o que está rodando, o que está parado, o que espera você). No Codex e no Gemini a regra entra nas instruções globais.
- Quando a IA começa um trabalho de verdade, chama `comecar_trabalho`: se já existe uma tarefa sua parecida, ela se pendura nela; se não, cria uma tarefa macro dela. Na dúvida, mostra as candidatas e escolhe.
- Subtarefa não vira item: vira etapa (`Claude · 3/7 · 40%`).
- Sessão que morreu no meio deixa a tarefa como "sem notícia há X min", e a próxima sessão vê isso ao começar.

### Conectar a IA

O `./instalar.sh` já conecta o servidor MCP (`mcp.py`) no que encontrar: Claude Code, Claude Desktop, Codex e Gemini CLI. Também liga o resumo de início de sessão (gancho `SessionStart` do Claude Code, em `scripts/sessao.py`) e um bloco marcado nas instruções globais do Codex (`~/.codex/AGENTS.md`) e do Gemini (`~/.gemini/GEMINI.md`). Pra rodar só essa parte: `./scripts/conectar-ia.sh` (e `--remover` pra desfazer). Em outra IA com MCP, aponte pra:

```
command: python3
args: /caminho/task-manager-mac/mcp.py
```

Ferramentas: `comecar_trabalho`, `perguntar`, `aguardar_resposta`, `listar_tarefas`, `adicionar_tarefa`, `definir_dono`, `pegar_tarefa`, `informar_progresso`, `concluir_tarefa`, `devolver_tarefa`, `marcar_feita`. As regras de triagem vão junto, nas instruções do servidor. O logo sai do nome que a IA informa ao conectar.

Sem MCP, o mesmo pelo terminal:

```bash
python3 tm.py dono t04 ia
python3 tm.py pegar t04 claude "lendo a conversa"
python3 tm.py progresso t04 60 "rascunhando a resposta"
python3 tm.py concluir t04 "Resposta pronta no rascunho" revisar
python3 tm.py devolver t04 "seu login na Amazon"
```

## Personalizar

- **Seções e títulos:** edite `dados/tarefas.json` (chave `secoes` e a ordem em `colunas`).
- **Visual:** tudo em `public/index.html`, com as cores em variáveis CSS no topo.
- **Posição e tamanho do widget da mesa:** `className` em `widget/task-manager.jsx`.
- **Porta:** variável `TM_PORTA` (padrão 8790). Se mudar, ajuste `BASE` em `barra-app/main.swift` e a URL do widget.
- Depois de mexer no app da barra: `./barra-app/instalar.sh` recompila.

## Versões

O histórico está em [CHANGELOG.md](CHANGELOG.md), e o app mostra as novidades da versão atual nos ajustes. Pra atualizar um Mac que já tem o app: `git pull && ./instalar.sh`.

## Desinstalar

```bash
./desinstalar.sh
```

Remove o serviço, o app e o widget. As tarefas em `dados/tarefas.json` ficam.

## Como é feito

```
mcp.py             servidor MCP (stdio) pro copiloto de IA
servidor.py        API local (GET /api/tarefas, POST /api/op) e arquivos da página
tm.py              núcleo: lê, altera e grava o JSON com trava e gravação atômica; também é a CLI
public/index.html  a página (modos: normal, ?app, ?widget, ?widget&largo, &moldura, &tema=claro|escuro)
barra-app/         app nativo em Swift (NSStatusItem + WKWebView), sem Xcode, compilado com swiftc; icone.swift gera o AppIcon.icns
widget/            widget do Übersicht
```

Visual baseado no guia de marca pessoal de Luan Sinézio: cinza neutro, IBM Plex Sans e Mono, grão leve.

## Licença

MIT
