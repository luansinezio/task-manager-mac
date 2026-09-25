# O que há de novo

Versões seguem `MAIOR.MENOR.CORREÇÃO`. Enquanto estiver em 0.x, MENOR sobe a cada recurso novo e CORREÇÃO a cada ajuste.
A primeira seção é a versão atual: é dela que o app lê o número e a lista de novidades.

## 0.5.0 — 2026-09-25

- A lista vira a barra de status de toda sessão de IA, não só das tarefas passadas pra ela
- Toda sessão do Claude Code começa com o resumo da lista: o que está rodando, o que está parado e o que espera você
- Codex e Gemini recebem a mesma regra nas instruções globais
- Só trabalho macro entra: a IA se pendura na sua tarefa correspondente ou cria uma tarefa macro dela; subtarefa vira etapa
- Nova ferramenta comecar_trabalho: acha a tarefa parecida ou cria, e pergunta quando tem dúvida
- Progresso por etapa na tela (Claude · 3/7 · 40%)
- Tarefa esquecida em andamento aparece como "sem notícia há X min", com a barra apagada
- A IA guarda o resultado (texto pronto ou arquivo) dentro da tarefa

## 0.4.0 — 2026-09-25

- Copiloto de IA: cada tarefa pode ser sua ou da IA
- Tarefa da IA mostra o logo de quem está fazendo (Claude, Codex, Gemini) e uma barra de progresso ao vivo
- Estados na tela: na fila, fazendo, revisar, feito pela IA, devolvida com o que falta
- Botão de faísca em cada tarefa passa pra IA ou pega de volta
- Servidor MCP: Claude Code, Claude Desktop, Codex e Gemini leem a lista, fazem a triagem, pegam tarefa, informam progresso e concluem
- O instalador conecta o MCP sozinho nas IAs que encontrar
- Regra da casa: a IA prepara, você dispara; o que sai pra fora fica em revisar até você marcar

## 0.3.0 — 2026-09-25

- Janela de verdade no modo Dock: arrasta, redimensiona, minimiza e lembra onde ficou
- A janela usa o layout compacto: uma coluna quando estreita, duas quando larga
- Botões da janela sempre visíveis, com margem em cima e sem título repetido
- Sem barra de rolagem na janela
- "Limpar feitas" virou um link discreto na linha da contagem
- Menus Editar e Janela: copiar, colar, ⌘W e ⌘M funcionam
- Seção "O que há de novo" nos ajustes

## 0.2.0 — 2026-09-25

- Engrenagem de ajustes no painel
- Escolha onde o app aparece: barra de menu, Dock ou os dois
- Liga e desliga o widget da mesa, o atalho do canto e o abrir no login
- Ícone próprio no Dock, com o número de tarefas abertas

## 0.1.2 — 2026-09-25

- Atalho da lista passa pro canto superior direito da tela

## 0.1.1 — 2026-09-25

- Painel do canto, barra de menu e widget acompanham a altura da lista

## 0.1.0 — 2026-09-25

- Primeira versão: página local, app de barra de menu, lista no centro pelo canto da tela e widget da mesa
- Tema claro e escuro seguindo o sistema
- Linha de comando `tm.py` pra scripts e agentes de IA
