# Changelog

## v2.0.0 (23 Set 2026)

Redesign de estabilidade + transparência real. Design visual do release inicial (v1.0.3) preservado.

### Correções

- **Transparência não funcionava (HUD cinza/preto)**: o Plasma desenha um fundo padrão (StandardBackground) atrás de todo applet de desktop, que tapava o wallpaper mesmo com o gradiente semi-transparente. Corrigido com `Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground` (sintaxe de propriedade anexada, aplicada no startup do plasmashell) + fallback no `Component.onCompleted`
- **Testar Conexão quebrado no Plasma 6**: `MessageDialog` via `createQmlObject` não funciona mais. Reescrito com feedback inline (✅/❌) direto na UI de config, com retry do `X-Transmission-Session-Id` (409)
- **Config UI corrompia bindings**: `Component.onCompleted` que sobrescrevia campos `cfg_*` removido

### Novas funcionalidades

- **Modo Econômico**: 4× menos updates, sem gráfico (para economizar CPU/bateria)
- **Máx. torrents na lista**: limita a lista de 5 a 50 itens (padrão 15)

### Limpeza

- Removidas credenciais hardcoded do source (agora só via configuração do widget)
- Removidos artefatos .zip/.plasmoid antigos do repo
- metadata.json/desktop padronizados (KPackageStructure, versão 2.0.0)

## v1.0.3 (31 Jul 2026) — Final Release

Versao final com correcoes de renderizacao do Canvas, estatisticas de sessao e totais acumulados.

### Correcoes

- **paintTick Connections (grafico em branco)**: `typeof dataCanvas !== "undefined"` falhava silenciosamente pois IDs dentro de fullRepresentation nao sao visiveis do root JS. Corrigido com `property int paintTick: 0` no root, incrementado em `updateUI()`, e `Connections { target: root; function onPaintTickChanged() { canvas.requestPaint() } }` dentro de cada Canvas
- **Texto sobreposto no header do grafico**: Speed values desenhados no Canvas nao participam do layout do QML. Substituido por `Text` nativos em `Row` — QML layout engine resolve espacamento automaticamente
- **Labels do eixo Y cortados**: `yAxisLabels.width` aumentado de 50 para 62, `anchors.rightMargin` reduzido de 8 para 4
- **Estatisticas "0 B" (chaves hifenadas RPC)**: Transmission RPC retorna `current-stats` e `cumulative-stats` com hifens. Acesso via bracket notation: `sessionStats["current-stats"].downloadedBytes` (dot notation retorna undefined)
- **Bloco solido no grafico**: Tres causas corrigidas: (1) maxSpeed sem margem — adicionado `maxSpeed * 1.2` (20% headroom); (2) X baseado em index nao timestamp — mudado para `((p.time - tMin) / tRange) * width`; (3) fills desenhados apos linhas — ordem invertida: fills primeiro, linhas por cima

### Novas funcionalidades

- Card de totais acumulados: novo card abaixo da lista de torrents mostrando total de download/upload de toda a vida do Transmission (cumulative-stats)
- Modo Tempo Real: `graphTimespan = 0` mostra todo o historico disponivel em vez de uma janela fixa

### Como instalar

1. Baixe o arquivo `transmission-monitor-v1.0.3.plasmoid` da pagina de Releases
2. No KDE Plasma: clique direito no panel ou desktop -> Editar Painel -> Adicionar Widgets -> [...] (menu) -> Instalar a partir de arquivo
3. Selecione o arquivo `.plasmoid` baixado
4. Execute no terminal: `kbuildsycoca6 --noincremental`
5. Adicione o widget ao panel ou desktop
6. Configure host, porta, usuario e senha do seu Transmission RPC nas configuracoes do widget

### Instalacao alternativa (manual)

```bash
mkdir -p ~/.local/share/plasma/plasmoids/org.kde.transmissionmonitor/
cp -r contents/ ~/.local/share/plasma/plasmoids/org.kde.transmissionmonitor/
cp metadata.json metadata.desktop ~/.local/share/plasma/plasmoids/org.kde.transmissionmonitor/
kbuildsycoca6 --noincremental
systemctl --user restart plasma-plasmashell.service
```

### Instalacao via kpackagetool6

```bash
kpackagetool6 --type Plasma/Applet --install transmission-monitor-v1.0.3.plasmoid
kbuildsycoca6 --noincremental
```

### Requisitos

- KDE Plasma 6.0 ou superior
- Transmission daemon com RPC habilitado
- Sonarr/Radarr enviando torrents com labels `sonarr`/`radarr` para o Transmission

---

## v1.0.2 (30 Jul 2026) — UI/UX Improvements

Melhorias de UI/UX, ScrollBar, SpinBox decimal e persistencia de configuracao.

### Correcoes

- ScrollBar Plasma: trocado `QQC2.ScrollBar` por `PlasmaComponents3.ScrollBar` — agora visivel mesmo com `clip: true` no fullRepresentation
- SpinBox decimal (truque x100): campos de vezespan do grafico armazenam valor como inteiro x100, convertido para display (500 -> 5.00 min). Permite granularidade de 0.05 min
- Timespan = 0 (Tempo Real): quando o vezespan e 0, o grafico mostra todo o historico (limitado a 300 pontos)
- main.xml KConfigXT: adicionado schema XML completo para todas as config keys — sem ele, novas propriedades nao persistiam ou nao propagavam bindings no Plasma 6
- KCM.SimpleKCM: ConfigGeneral.qml agora usa `KCM.SimpleKCM` como root, que fornece scroll automatico para forms longos
- Correcao de overflow: adicionado `clip: true` no fullRepresentation Item; graph usa `Layout.preferredHeight` + `Layout.maximumHeight` em vez de `Layout.fillHeight` competindo com ListView
- Elide no titulo: `PlasmaComponents3.Label` com `elide: Text.ElideRight` no header evita sobreposicao com botao de status

---

## v1.01 (29 Jul 2026) — Regression Fixes

Correcoes de regressao e melhorias de robustez apos a versao inicial.

### Correcoes

- Acesso direto a Item nas representacoes: Removido o wrapper `Component {}` que causava `Expected token '}'` e escondia IDs do root scope
- Property bindings no lugar de JS assignments: Textos no compactRepresentation agora usam bindings (`text: root.hasData ? ... : "--"`) em vez de `.text =` assignments que falhavam silenciosamente
- ListView com property var: Substituido `ListModel` (inacessivel do root scope) por `property var torrentRows: []` com `model: root.torrentRows` e `modelData.xxx` nos delegates
- Leitura dinamica de config: `plasmoid.configuration.host` agora e lido dentro das funcoes a cada chamada, nao capturado em property na inicializacao

---

## v1.0 (27 Jul 2026) — Initial Release

Primeira versao publica do widget KDE Plasma 6 para monitorar o Transmission RPC integrado com Sonarr/Radarr.

### Funcionalidades

- Cards de velocidade em tempo real (Download/Upload com auto-formatacao B/s, KB/s, MB/s)
- Grafico de velocidade ao vivo com linhas de download/upload, grid e eixos rotulados
- Lista de torrents filtrada — mostra apenas torrents marcados como `sonarr` ou `radarr` no Transmission
- Status individual: progresso (%), velocidades, ETA, peers, status (Enfileirado, Baixando, Semeando, Pausado)
- Configuracao persistente via KConfigXT: host, porta, usuario, senha, caminho RPC, intervalo de atualizacao
- Suporte a Plasma 6 (metadata.json com KPlugin, X-Plasma-API-Minimum-Version 6.0)
- Transparencia nativa do PlasmoidItem (sem background forcado)
- Cores de tema customizadas (accent cyan/purple, graph lines)

### Creditos

- Idealizacao e direcao: Amielle
- Implementacao: Hermes Agent (Nous Research)
