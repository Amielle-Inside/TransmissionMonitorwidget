# Transmission Monitor — KDE Plasma 6 Widget

Um widget nativo para KDE Plasma 6 que monitora o Transmission RPC em tempo real, filtrando torrents por categorias do Sonarr/Radarr, com gráfico de velocidade ao vivo e estatísticas acumuladas.

---

## Sobre a Criação

Este widget foi criado com **[Hermes Agent](https://github.com/NousResearch/hermes-agent)** — um agente de IA desenvolvido pela **[Nous Research](https://www.nousresearch.com/)**.

A criadora deste projeto **não é desenvolvedora de software**. A ideia surgiu da necessidade real de monitorar a rede de um Arr Stack (Sonarr + Radarr + Transmission) em tempo real, diretamente no desktop KDE Plasma. Como não havia um widget que atendesse a essa necessidade específica — monitorar apenas os torrents gerenciados pelo Sonarr/Radarr com gráfico em tempo real —, a solução foi usar um agente de IA que pudesse escrever o código QML necessário a partir das descrições do que se queria.

O Hermes Agent foi escolhido por sua capacidade de:
- Iterar rapidamente entre código e teste visual (escrever QML → reiniciar Plasma → ajustar)
- Debugar problemas de escopo QML do Plasma 6 que são não-intuitivos
- Aprender com os erros e documentar as soluções (skills persistentes)
- Trabalhar com o usuário em português brasileiro

Todo o código fonte, estrutura do plasmoid, lógica de RPC, Canvas do gráfico, e UI foram escritos pelo agente de IA com direção e feedback da criadora.

---

## Funcionalidades

- **Cards de velocidade em tempo real** — Download, Upload (B/s, KB/s, MB/s auto-formatado)
- **Gráfico de velocidade ao vivo** — Linhas de download/upload com fill, grid e eixos rotulados
- **Lista de torrents filtrada** — Mostra apenas torrents marcados como `sonarr` ou `radarr` no Transmission
- **Status individual** — Progresso (%), velocidades, ETA, peers, status (Enfileirado, Baixando, Semeando, Pausado)
- **Estatísticas de sessão** — Total de download/upload desde o início da sessão atual do Transmission
- **Estatísticas acumuladas** — Total de download/upload de toda a vida do Transmission
- **Botão de teste de conexão** — Valida as credenciais RPC antes de salvar
- **Configuração persistente** — Host, porta, usuário, senha, caminho RPC, intervalo de atualização, título do widget, e vezespan do gráfico são salvos via KConfigXT
- **Tema escuro customizado** — Cores neon (cyan + rosa) sobre fundo charcoal, independente do tema do Plasma

---

## Requisitos

| Componente | Versão Mínima | Notas |
|---|---|---|
| **KDE Plasma** | 6.0+ | O widget usa a API declarativa do Plasma 6 (`PlasmoidItem`, `PlasmaComponents3`) |
| **Qt** | 6.0+ | Import `QtQuick` sem versão explícita (QML 3) |
| **Transmission** | 2.40+ | Com RPC habilitado |
| **Sonarr** | qualquer | Opcional — filtro funciona por categoria/label no Transmission |
| **Radarr** | qualquer | Opcional — filtro funciona por categoria/label no Transmission |
| **Distro** | qualquer distro com Plasma 6 | Testado em Bazzite (Fedora Atomic), Fedora, Arch |

>  **Não compatível com KDE Plasma 5** — O widget usa `PlasmoidItem` (não `PlasmaWidgets.Applet`), `metadata.json` com `KPlugin`, e `X-Plasma-API-Minimum-Version: "6.0"`.

---

## Instalação

### Método 1: Instalar via arquivo (recomendado)

1. Baixe o arquivo `transmission-monitor.plasmoid` (ou `.zip`) da página de [Releases](../../releases)
2. No KDE Plasma, clique com o botão direito no desktop ou painel → **Adicionar Widgets** → **⋮** → **Instalar do arquivo**
3. Selecione o arquivo baixado
4. O widget aparecerá na lista de widgets disponíveis

### Método 2: Instalação manual

```bash
# 1. Clone o repositório
git clone https://github.com/Amielle-Inside/TransmissionMonitorwidget.git
cd transmission-monitor

# 2. Copie a estrutura para o diretório de plasmoids do usuário
mkdir -p ~/.local/share/plasma/plasmoids/org.kde.transmissionmonitor
cp -r * ~/.local/share/plasma/plasmoids/org.kde.transmissionmonitor/

# 3. Reconstrua o cache do sistema (obrigatório)
kbuildsycoca6 --noincremental

# 4. Reinicie o Plasma (um dos dois)
# Opção A — via systemctl:
systemctl --user restart plasma-plasmashell.service
# Opção B — logout e login
```

### Método 3: Instalar via kpackagetool6

```bash
git clone https://github.com/Amielle-Inside/TransmissionMonitorwidget.git
cd transmission-monitor
kpackagetool6 --type Plasma/Applet --install .
```

---

## Configuração

Após adicionar o widget ao desktop ou painel:

1. Clique com o botão direito no widget → **Configurar**
2. Preencha os dados do Transmission RPC:

| Campo | Descrição | Padrão |
|---|---|---|
| **Host** | IP ou hostname do Transmission | `localhost` |
| **Porta** | Porta RPC do Transmission | `9091` |
| **Usuário** | Usuário RPC (deixe vazio se não usar auth) | *(vazio)* |
| **Senha** | Senha RPC (deixe vazio se não usar auth) | *(vazio)* |
| **Caminho RPC** | Path do endpoint RPC | `/transmission/rpc` |
| **Intervalo** | Frequência de atualização (ms) | `2000` |
| **Título do Widget** | Nome exibido no header | `Arr Stack` |
| **Mostrar gráfico** | Exibir/ocultar o gráfico de velocidade | `true` |
| **Tempospan do gráfico** | Janela de tempo em minutos (0 = tempo real) | `0` |

3. Clique em **Testar Conexão** — se mostrar , está pronto
4. Clique em **OK**

>  **Dica:** Para que o filtro funcione, seus torrents do Sonarr/Radarr precisam estar marcados com as categorias `sonarr` ou `radarr` no Transmission. O Sonarr e Radarr fazem isso automaticamente ao enviar torrents para o Transmission.

---

## Como Funciona

### Arquitetura

```
org.kde.transmissionmonitor/
├── metadata.json             # Metadata do plugin (Plasma 6 KPlugin)
├── metadata.desktop          # Metadata legado (compatibilidade)
└── contents/
    ├── ui/
    │   ├── main.qml          # UI principal + lógica RPC + Canvas do gráfico
    │   └── ConfigGeneral.qml # Interface de configuração
    ├── config/
    │   ├── config.qml        # ConfigModel apontando para ConfigGeneral.qml
    │   └── main.xml          # Schema KConfigXT (persistência das config)
    └── code/
        └── main.js           # Helper de teste de conexão (chamado pela config UI)
```

### Fluxo de Dados

1. **Timer** disputa a cada `updateInterval` ms (padrão 2000ms)
2. `fetchData()` faz chamada RPC ao Transmission via `XMLHttpRequest` síncrono (POST)
3. Três métodos RPC são chamados: `session-stats`, `torrent-get` (com filtro)
4. `updateUI()` processa a resposta e atualiza as properties do root
5. QML bindings reagem automaticamente: cards, lista de torrents, texto do gráfico
6. Canvas do gráfico é repintado via pattern `paintTick` (incrementa → `Connections` dispara `requestPaint()`)
7. Lista de torrents é filtrada client-side: apenas torrents com `labels` contendo `sonarr` ou `radarr`

### Filtro de Torrents

O widget consulta todos os torrents ativos do Transmission e filtra no client-side:

```javascript
var labels = t.labels || []
var isArr = labels.some(function(l) {
    return l === "sonarr" || l === "radarr"
})
```

Apenas torrents marcados são exibidos na lista.

### Transmission RPC

O widget usa o endpoint RPC do Transmission (`POST /transmission/rpc`):

1. Primeira requisição pode retornar `409` com header `X-Transmission-Session-Id`
2. O código captura esse header e refaz a requisição com ele
3. Autenticação via Basic Auth (`Authorization: Base64...s)`)

**Métodos usados:**

| Método | Uso |
|---|---|
| `session-stats` | Velocidades atuais + estatísticas de sessão e acumuladas |
| `torrent-get` | Lista de torrents com nome, status, progresso, velocidades, peers, labels |

### Gráfico em Tempo Real

O gráfico é desenhado em um `Canvas` QML:

- **3 camadas de Canvas**: `gridCanvas` (grid + eixos + labels), `dataCanvas` (linhas + fills), `speedCanvas` (valores atuais)
- **Pattern `paintTick`**: Como IDs dentro de `fullRepresentation` não são visíveis do escopo root, um contador `property int paintTick` no root é incrementado a cada update. Cada Canvas observa via `Connections { target: root; function onPaintTickChanged() { requestPaint() } }`
- **Headroom de 20%**: `maxSpeed * 1.2` garante que a linha nunca encoste no topo
- **Fill antes de lines**: Fills de upload/download são desenhados primeiro, linhas por cima, evitando sólido block
- **Time-based X-axis**: Pontos são posicionados por timestamp, não por índice

---

## Build from Source

### Pré-requisitos

- KDE Plasma 6 development packages (já incluído em qualquer instalação do Plasma 6)
- `kpackagetool6` (parte do pacote `plasma-framework` ou `plasma5-sdk`)
- `git`

### Passo a passo

```bash
# 1. Clone
git clone https://github.com/Amielle-Inside/TransmissionMonitorwidget.git
cd transmission-monitor

# 2. Verifique a estrutura
ls -la
# Deve conter: metadata.json, metadata.desktop, contents/

# 3. Empacote como .plasmoid
zip -r transmission-monitor.plasmoid \
    metadata.json \
    metadata.desktop \
    contents/

# 4. Instale o pacote
kpackagetool6 --type Plasma/Applet --install transmission-monitor.plasmoid

# 5. Reconstrua o cache do sistema
kbuildsycoca6 --noincremental

# 6. Reinicie o Plasma
systemctl --user restart plasma-plasmashell.service

# 7. Adicione o widget:
# Clique direito no desktop → Adicionar Widgets → procure "Transmission Monitor"
```

### Para atualizar uma instalação existente

```bash
# Após fazer alterações no código:
kpackagetool6 --type Plasma/Applet --upgrade transmission-monitor.plasmoid
rm -rf ~/.cache/plasma*  # limpar cache QML
systemctl --user restart plasma-plasmashell.service
```

### Para desinstalar

```bash
kpackagetool6 --type Plasma/Applet --remove org.kde.transmissionmonitor
```

---

## Troubleshooting

| Problema | Solução |
|---|---|
| Widget não aparece na lista | Execute `kbuildsycoca6 --noincremental` |
| "Widget sem suporte" | Verifique se seu Plasma é versão 6.0+ |
| Gráfico vazio mas dados chegam | Reinicie o Plasma após instalar (`systemctl --user restart plasma-plasmashell`) |
| "Sessão: 0 B" sempre | Confirme que o Transmission RPC está acessível (`curl http://host:9091/transmission/rpc`) |
| Lista de torrents vazia | Verifique se seus torrents têm labels `sonarr` ou `radarr` no Transmission |
| 409 Conflict | É normal — o widget trata isso automaticamente |
| Erro de auth 401 | Verifique usuário e senha do RPC nas configurações |

---

## Estrutura de Arquivos

```
transmission-monitor/
├── metadata.json             # KPlugin JSON (Plasma 6 obrigatório)
├── metadata.desktop          # Desktop entry (compatibilidade)
├── contents/
│   ├── ui/
│   │   ├── main.qml          # ~850 linhas — UI + RPC + Canvas
│   │   └── ConfigGeneral.qml # Interface de configuração (KCM.SimpleKCM)
│   ├── config/
│   │   ├── config.qml        # ConfigModel → ConfigGeneral.qml
│   │   └── main.xml          # KConfigXT schema (10 propriedades)
│   └── code/
│       └── main.js           # testConnection() helper
└── README.md                 # Este arquivo
```

---

## Licença

MIT License — sinta-se livre para usar, modificar e distribuir.

---

## Créditos

- **Idealização e direção:** [Amielle](https://github.com/Amielle-Inside) ‍
- **Implementação:** [Hermes Agent](https://github.com/NousResearch/hermes-agent) (IA) com correções e feedback da criadora

---

## Agradecimentos

- [Nous Research](https://www.nousresearch.com/) pelo desenvolvimento do Hermes Agent
- KDE Community pelo Plasma 6 e PlasmaComponents3
- Transmission Project pelo excelente cliente de torrent e RPC
