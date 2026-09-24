import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore

PlasmoidItem {
    id: root

    // Remove o fundo padrão do Plasma (o "HUD" cinza/preto atrás do widget)
    // para que o gradiente customizado e a transparência funcionem de verdade.
    // Sintaxe de propriedade anexada (igual ao org.kde.kdeconnect):
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    // Desktop widget resize hints
    Layout.minimumWidth: 360
    Layout.minimumHeight: 380
    Layout.preferredWidth: 400
    Layout.preferredHeight: 520

    // When on desktop, show full representation directly;
    // PlasmoidItem handles this automatically

    // Reactive config bindings
    property string widgetTitle: plasmoid.configuration.widgetTitle !== undefined ? plasmoid.configuration.widgetTitle : "Transmission Monitor"
    property int updateInterval: plasmoid.configuration.updateInterval || 5000
    property bool showGraph: plasmoid.configuration.showGraph !== false
    // graphTimespan is stored as int × 100 (e.g. 500 = 5.00 min). 0 = realtime/unlimited.
    property real graphTimespan: (plasmoid.configuration.graphTimespan !== undefined ? plasmoid.configuration.graphTimespan : 500) / 100.0
    property int transparency: plasmoid.configuration.transparency !== undefined ? plasmoid.configuration.transparency : 0
    property int themeIndex: plasmoid.configuration.themeIndex !== undefined ? plasmoid.configuration.themeIndex : 0

    // State
    property var sessionStats: ({})
    property var torrents: []
    property var torrentRows: []  // pre-formatted rows for ListView
    property var speedHistory: []
    property string sessionId: ""
    property bool connected: false
    property bool hasData: false
    property string lastError: ""
    property int maxHistoryPoints: 300

    // Monotonically increasing tick used to trigger canvas repaints
    // from root scope (IDs inside fullRepresentation are NOT visible from root JS)
    property int paintTick: 0

    // ==================== THEME ENGINE ====================
    // themeIndex: 0=Synthwave 1=Leve/Transparente 2=Cyberpunk 2077 3=Matrix 4=AMOLED 5=Personalizado
    readonly property var themes: ({
        0: { bgStart: "#2a1b3d", bgEnd: "#1a0b2e", accent: "#00e8ff", accent2: "#ff75da", accent3: "#a05bff",
             down: "#3daee9", up: "#f05050", text: "#ffffff", muted: "#a89fbb", warn: "#ffb84d", crit: "#ff4757",
             border: 1, radius: root.themedRadius },
        1: { bgStart: "#2a1b3d", bgEnd: "#1a0b2e", accent: "#00e8ff", accent2: "#ff75da", accent3: "#a05bff",
             down: "#3daee9", up: "#f05050", text: "#ffffff", muted: "#a89fbb", warn: "#ffb84d", crit: "#ff4757",
             border: 0, radius: root.themedRadius, transparentCards: true },
        2: { bgStart: "#1a0e1f", bgEnd: "#0d0610", accent: "#fcee0a", accent2: "#ff003c", accent3: "#00f0ff",
             down: "#00f0ff", up: "#ff003c", text: "#f5f5dc", muted: "#9c8fa3", warn: "#fcee0a", crit: "#ff003c",
             border: 2, radius: 2 },
        3: { bgStart: "#001500", bgEnd: "#000800", accent: "#00ff41", accent2: "#00cc33", accent3: "#008f2b",
             down: "#00ff41", up: "#66ff99", text: "#00ff41", muted: "#00a828", warn: "#d4ff00", crit: "#ff3333",
             border: 1, radius: 0 },
        4: { bgStart: "#000000", bgEnd: "#000000", accent: "#ffffff", accent2: "#b3b3b3", accent3: "#666666",
             down: "#e6e6e6", up: "#999999", text: "#ffffff", muted: "#888888", warn: "#cccccc", crit: "#ffffff",
             border: 1, radius: 16 },
        5: null  // custom — resolved from configuration
    })
    property var activeTheme: {
        if (themeIndex === 5) {
            return {
                bgStart: plasmoid.configuration.customBgStart || "#2a1b3d",
                bgEnd: plasmoid.configuration.customBgEnd || "#1a0b2e",
                accent: plasmoid.configuration.customAccent || "#00e8ff",
                accent2: plasmoid.configuration.customAccent2 || "#ff75da",
                accent3: plasmoid.configuration.customAccent || "#00e8ff",
                down: plasmoid.configuration.customDownload || "#3daee9",
                up: plasmoid.configuration.customUpload || "#f05050",
                text: plasmoid.configuration.customText || "#ffffff",
                muted: plasmoid.configuration.customTextMuted || "#a89fbb",
                warn: plasmoid.configuration.customWarning || "#ffb84d",
                crit: plasmoid.configuration.customCritical || "#ff4757",
                border: Math.max(0, Math.min(4, plasmoid.configuration.borderWidth !== undefined ? plasmoid.configuration.borderWidth : 1)),
                radius: Math.max(0, Math.min(24, plasmoid.configuration.cornerRadius !== undefined ? plasmoid.configuration.cornerRadius : 12))
            }
        }
        return themes[themeIndex] || themes[0]
    }

    // Colors (resolved from theme — custom* configs override when themeIndex=5)
    property color colorBgStart: activeTheme.bgStart
    property color colorBgEnd: activeTheme.bgEnd
    property color colorAccentCyan: activeTheme.accent
    property color colorAccentPink: activeTheme.accent2
    property color colorAccentPurple: activeTheme.accent3
    property color colorDownload: activeTheme.down
    property color colorUpload: activeTheme.up
    property color colorWarning: activeTheme.warn
    property color colorCritical: activeTheme.crit
    property color colorTextMuted: activeTheme.muted
    property color colorText: activeTheme.text

    // Typography scale (all font.pixelSize values use fs(n))
    property real fontScaleF: Math.max(0.8, Math.min(1.4, (plasmoid.configuration.fontScale !== undefined ? plasmoid.configuration.fontScale : 100) / 100.0))
    function fs(base) { return Math.round(base * root.fontScaleF) }

    property int themedBorderWidth: activeTheme.border
    property int themedRadius: activeTheme.radius

    property real backdropOpacity: transparency / 100.0 * 0.9 + 0.1

    toolTipMainText: root.widgetTitle
    toolTipSubText: {
        if (!hasData) return "Connecting..."
        return "⬇ " + formatSpeed(sessionStats.downloadSpeed || 0) + "  ⬆ " + formatSpeed(sessionStats.uploadSpeed || 0)
    }

    // ==========================================
    // COMPACT REPRESENTATION (Panel)
    // ==========================================
    compactRepresentation: Item {
        id: compactRep
        Layout.minimumWidth: 90
        Layout.minimumHeight: Kirigami.Units.iconSizes.small
        Layout.preferredWidth: 120
        Layout.preferredHeight: Layout.minimumHeight
        Layout.margins: 4

        Row {
            anchors.centerIn: parent
            spacing: 4

            Text {
                id: compactDlText
                text: root.hasData ? "▼ " + formatSpeed(root.sessionStats.downloadSpeed || 0) : "▼ --"
                font.pixelSize: fs(11)
                font.family: "JetBrains Mono, Noto Sans Mono, monospace"
                font.bold: true
                color: root.colorDownload
                verticalAlignment: Text.AlignVCenter
            }

            Text {
                text: "│"
                font.pixelSize: fs(11)
                color: root.colorTextMuted
                verticalAlignment: Text.AlignVCenter
            }

            Text {
                id: compactUlText
                text: root.hasData ? "▲ " + formatSpeed(root.sessionStats.uploadSpeed || 0) : "▲ --"
                font.pixelSize: fs(11)
                font.family: "JetBrains Mono, Noto Sans Mono, monospace"
                font.bold: true
                color: root.colorUpload
                verticalAlignment: Text.AlignVCenter
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.expanded = !root.expanded
            cursorShape: Qt.PointingHandCursor
        }
    }

    // ==========================================
    // FULL REPRESENTATION (Popup)
    // ==========================================
    fullRepresentation: Item {
        id: fullRep
        Layout.minimumWidth: 360
        Layout.minimumHeight: 380
        Layout.preferredWidth: 400
        Layout.preferredHeight: 520
        Layout.maximumWidth: 800
        Layout.maximumHeight: 1200
        // CRITICAL: clip everything to the widget bounds so content
        // can never overflow the visible area
        clip: true

        Rectangle {
            id: backdrop
            anchors.fill: parent
            radius: 16
            visible: true
            gradient: Gradient {
                GradientStop { position: 0.0; color: root.colorBgStart }
                GradientStop { position: 1.0; color: root.colorBgEnd }
            }
            border.color: Qt.rgba(root.colorAccentPink.r, root.colorAccentPink.g, root.colorAccentPink.b, 0.3)
            border.width: root.themedBorderWidth
            opacity: root.backdropOpacity
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            // HEADER
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Item {
                    width: 32
                    height: 32

                    Canvas {
                        id: transmissionIcon
                        anchors.fill: parent
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            var cx = width / 2
                            var cy = height / 2
                            var r = width / 2 - 2

                            ctx.strokeStyle = root.colorAccentCyan
                            ctx.lineWidth = 2.5
                            ctx.beginPath()
                            ctx.arc(cx, cy, r, 0, 2 * Math.PI)
                            ctx.stroke()

                            ctx.fillStyle = root.colorAccentCyan
                            ctx.beginPath()
                            ctx.moveTo(cx, cy - 4)
                            ctx.lineTo(cx + 4, cy + 2)
                            ctx.lineTo(cx - 4, cy + 2)
                            ctx.closePath()
                            ctx.fill()

                            ctx.fillStyle = root.colorAccentPink
                            ctx.beginPath()
                            ctx.moveTo(cx, cy + 4)
                            ctx.lineTo(cx + 4, cy - 2)
                            ctx.lineTo(cx - 4, cy - 2)
                            ctx.closePath()
                            ctx.fill()
                        }
                    }
                }

                PlasmaComponents3.Label {
                    text: root.widgetTitle
                    font.pixelSize: fs(20)
                    font.bold: true
                    font.family: "Inter, Noto Sans, sans-serif"
                    color: root.colorAccentPink
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Rectangle {
                    color: root.connected ? Qt.rgba(root.colorAccentCyan.r, root.colorAccentCyan.g, root.colorAccentCyan.b, 0.15)
                                       : Qt.rgba(root.colorCritical.r, root.colorCritical.g, root.colorCritical.b, 0.15)
                    border.color: root.connected ? root.colorAccentCyan : root.colorCritical
                    border.width: root.themedBorderWidth
                    radius: root.themedRadius
                    Layout.preferredWidth: statusText.width + 24
                    Layout.preferredHeight: 28

                    Text {
                        id: statusText
                        anchors.centerIn: parent
                        text: root.connected ? "Conectado" : "Desconectado"
                        font.pixelSize: fs(12)
                        font.bold: true
                        color: root.connected ? root.colorAccentCyan : root.colorCritical
                    }
                }
            }

            // QUICK STATS ROW
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                // Download Card
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 65

                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                        color: Qt.rgba(0, 0, 0, 0.25)
                        border.color: Qt.rgba(root.colorDownload.r, root.colorDownload.g, root.colorDownload.b, 0.4)
                        border.width: root.themedBorderWidth
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 2

                        Text {
                            text: "⬇ Download"
                            font.pixelSize: fs(11)
                            color: root.colorTextMuted
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Text {
                            id: dlSpeedText
                            text: root.hasData ? formatSpeed(root.sessionStats.downloadSpeed || 0) : "-- B/s"
                            font.bold: true
                            font.pixelSize: fs(16)
                            font.family: "JetBrains Mono, Noto Sans Mono, monospace"
                            color: root.colorDownload
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Text {
                            id: dlSessionText
                            text: "Sessão: " + formatBytes(root.sessionStats["current-stats"] ? (root.sessionStats["current-stats"].downloadedBytes || 0) : 0)
                            font.pixelSize: fs(10)
                            color: root.colorTextMuted
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }

                // Upload Card
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 65

                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                        color: Qt.rgba(0, 0, 0, 0.25)
                        border.color: Qt.rgba(root.colorUpload.r, root.colorUpload.g, root.colorUpload.b, 0.4)
                        border.width: root.themedBorderWidth
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 2

                        Text {
                            text: "⬆ Upload"
                            font.pixelSize: fs(11)
                            color: root.colorTextMuted
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Text {
                            id: ulSpeedText
                            text: root.hasData ? formatSpeed(root.sessionStats.uploadSpeed || 0) : "-- B/s"
                            font.bold: true
                            font.pixelSize: fs(16)
                            font.family: "JetBrains Mono, Noto Sans Mono, monospace"
                            color: root.colorUpload
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Text {
                            id: ulSessionText
                            text: "Sessão: " + formatBytes(root.sessionStats["current-stats"] ? (root.sessionStats["current-stats"].uploadedBytes || 0) : 0)
                            font.pixelSize: fs(10)
                            color: root.colorTextMuted
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }

                // Active Torrents Card
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 65

                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                        color: Qt.rgba(0, 0, 0, 0.25)
                        border.color: Qt.rgba(root.colorAccentPurple.r, root.colorAccentPurple.g, root.colorAccentPurple.b, 0.4)
                        border.width: root.themedBorderWidth
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 2

                        Text {
                            text: "📦 Ativos"
                            font.pixelSize: fs(11)
                            color: root.colorTextMuted
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Text {
                            id: activeCountText
                            text: root.torrents ? root.torrents.length : "0"
                            font.bold: true
                            font.pixelSize: fs(22)
                            color: root.colorText
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Text {
                            text: "torrents"
                            font.pixelSize: fs(10)
                            color: root.colorTextMuted
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }
            }

            // GRAPH
            Item {
                id: graphContainer
                Layout.fillWidth: true
                Layout.preferredHeight: 180
                Layout.maximumHeight: 200
                visible: root.showGraph

                Rectangle {
                    anchors.fill: parent
                    radius: root.themedRadius
                    color: root.activeTheme.transparentCards === true ? "transparent" : Qt.rgba(0, 0, 0, 0.2)
                    border.color: Qt.rgba(root.colorAccentPurple.r, root.colorAccentPurple.g, root.colorAccentPurple.b, 0.4)
                    border.width: root.activeTheme.transparentCards === true ? 0 : root.themedBorderWidth
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: root.graphTimespan === 0 ? "Velocidade (Tempo Real)" : "Velocidade (" + root.graphTimespan.toFixed(2) + " min)"
                            font.pixelSize: fs(14)
                            font.bold: true
                            color: root.colorAccentPurple
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        Row {
                            spacing: 6
                            Layout.preferredHeight: 22

                            Text {
                                text: "▼"
                                font.pixelSize: fs(12)
                                color: root.colorDownload
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                id: dlSpeedLabel
                                text: root.hasData ? formatSpeed(root.sessionStats.downloadSpeed || 0) : "-- B/s"
                                font.pixelSize: fs(12)
                                font.bold: true
                                font.family: "JetBrains Mono, Noto Sans Mono, monospace"
                                color: root.colorDownload
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "▲"
                                font.pixelSize: fs(12)
                                color: root.colorUpload
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                id: ulSpeedLabel
                                text: root.hasData ? formatSpeed(root.sessionStats.uploadSpeed || 0) : "-- B/s"
                                font.pixelSize: fs(12)
                                font.bold: true
                                font.family: "JetBrains Mono, Noto Sans Mono, monospace"
                                color: root.colorUpload
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }

                    // Chart Canvas
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 80

                        Item {
                            id: yAxisLabels
                            width: 62
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 20

                            Repeater {
                                model: 6
                                Text {
                                    text: {
                                        var maxSpeed = getMaxSpeed()
                                        return formatSpeed(maxSpeed - index * (maxSpeed / 5))
                                    }
                                    font.pixelSize: fs(10)
                                    font.bold: true
                                    y: (parent.height / 5) * index - height/2
                                    anchors.right: parent.right
                                    anchors.rightMargin: 4
                                    color: root.colorTextMuted
                                }
                            }
                        }

                        Item {
                            anchors.left: yAxisLabels.right
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: 8
                            anchors.bottomMargin: 20

                            Canvas {
                                id: gridCanvas
                                anchors.fill: parent
                                onWidthChanged: requestPaint()
                                onHeightChanged: requestPaint()
                                onVisibleChanged: if (visible) requestPaint()
                                Connections {
                                    target: root
                                    function onPaintTickChanged() { gridCanvas.requestPaint() }
                                }
                                onPaint: {
                                    var ctx = getContext("2d")
                                    ctx.clearRect(0, 0, width, height)
                                    ctx.strokeStyle = Qt.rgba(root.colorAccentPurple.r, root.colorAccentPurple.g, root.colorAccentPurple.b, 0.15)
                                    ctx.lineWidth = 1

                                    for (var i = 0; i <= 5; i++) {
                                        var y = (height / 5) * i
                                        ctx.beginPath()
                                        ctx.moveTo(0, y)
                                        ctx.lineTo(width, y)
                                        ctx.stroke()
                                    }

                                    var timeDivs = root.graphTimespan === 0 ? 10 : root.graphTimespan * 2
                                    for (var i = 0; i <= timeDivs; i++) {
                                        var x = (width / timeDivs) * i
                                        ctx.beginPath()
                                        ctx.moveTo(x, 0)
                                        ctx.lineTo(x, height)
                                        ctx.stroke()
                                    }
                                }
                            }
                            Canvas {
                                id: dataCanvas
                                anchors.fill: parent
                                onWidthChanged: requestPaint()
                                onHeightChanged: requestPaint()
                                onVisibleChanged: if (visible) requestPaint()
                                Connections {
                                    target: root
                                    function onPaintTickChanged() { dataCanvas.requestPaint() }
                                }
                                onPaint: {
                                    var ctx = getContext("2d")
                                    ctx.clearRect(0, 0, width, height)
                                    if (root.speedHistory.length < 2) return

                                    var now = Date.now()
                                    var ts = root.graphTimespan
                                    // Fallback if NaN/undefined
                                    if (ts === undefined || isNaN(ts)) ts = 5.0
                                    var timeSpanMs = ts === 0 ? 0 : ts * 60 * 1000
                                    var minTime = timeSpanMs === 0 ? 0 : (now - timeSpanMs)

                                    var validPoints = timeSpanMs === 0 ? root.speedHistory : root.speedHistory.filter(function(p) { return p.time >= minTime })
                                    if (validPoints.length < 2) return

                                    var maxDown = Math.max.apply(null, validPoints.map(function(p) { return p.down }))
                                    var maxUp = Math.max.apply(null, validPoints.map(function(p) { return p.up }))
                                    var maxSpeed = Math.max(maxDown, maxUp, 1)
                                    // Add 20% headroom so the line isn't at the very top
                                    maxSpeed = maxSpeed * 1.2

                                    var tMin = validPoints[0].time
                                    var tMax = validPoints[validPoints.length - 1].time
                                    var tRange = tMax - tMin
                                    if (tRange === 0) tRange = 1

                                    // --- Fills first (behind lines) ---
                                    // Fill download area
                                    ctx.fillStyle = Qt.rgba(root.colorDownload.r, root.colorDownload.g, root.colorDownload.b, 0.08)
                                    ctx.beginPath()
                                    validPoints.forEach(function(p, idx) {
                                        var x = ((p.time - tMin) / tRange) * width
                                        var y = height - (height * (p.down / maxSpeed))
                                        if (idx === 0) {
                                            ctx.moveTo(x, height)
                                            ctx.lineTo(x, y)
                                        } else {
                                            ctx.lineTo(x, y)
                                        }
                                    })
                                    ctx.lineTo(((validPoints[validPoints.length-1].time - tMin) / tRange) * width, height)
                                    ctx.lineTo(((validPoints[0].time - tMin) / tRange) * width, height)
                                    ctx.closePath()
                                    ctx.fill()

                                    // Fill upload area
                                    ctx.fillStyle = Qt.rgba(root.colorUpload.r, root.colorUpload.g, root.colorUpload.b, 0.08)
                                    ctx.beginPath()
                                    validPoints.forEach(function(p, idx) {
                                        var x = ((p.time - tMin) / tRange) * width
                                        var y = height - (height * (p.up / maxSpeed))
                                        if (idx === 0) {
                                            ctx.moveTo(x, height)
                                            ctx.lineTo(x, y)
                                        } else {
                                            ctx.lineTo(x, y)
                                        }
                                    })
                                    ctx.lineTo(((validPoints[validPoints.length-1].time - tMin) / tRange) * width, height)
                                    ctx.lineTo(((validPoints[0].time - tMin) / tRange) * width, height)
                                    ctx.closePath()
                                    ctx.fill()

                                    // --- Lines on top of fills ---
                                    // Download line
                                    ctx.strokeStyle = root.colorDownload
                                    ctx.lineWidth = 2.5
                                    ctx.lineCap = "round"
                                    ctx.lineJoin = "round"
                                    ctx.beginPath()
                                    validPoints.forEach(function(p, idx) {
                                        var x = ((p.time - tMin) / tRange) * width
                                        var y = height - (height * (p.down / maxSpeed))
                                        if (idx === 0) ctx.moveTo(x, y)
                                        else ctx.lineTo(x, y)
                                    })
                                    ctx.stroke()

                                    // Upload line
                                    ctx.strokeStyle = root.colorUpload
                                    ctx.lineWidth = 2.5
                                    ctx.beginPath()
                                    validPoints.forEach(function(p, idx) {
                                        var x = ((p.time - tMin) / tRange) * width
                                        var y = height - (height * (p.up / maxSpeed))
                                        if (idx === 0) ctx.moveTo(x, y)
                                        else ctx.lineTo(x, y)
                                    })
                                    ctx.stroke()

                                    // Current value dots
                                    var last = validPoints[validPoints.length - 1]
                                    var lastX = ((last.time - tMin) / tRange) * width

                                    ctx.fillStyle = root.colorDownload
                                    ctx.beginPath()
                                    ctx.arc(lastX, height - (height * (last.down / maxSpeed)), 3, 0, 2 * Math.PI)
                                    ctx.fill()

                                    ctx.fillStyle = root.colorUpload
                                    ctx.beginPath()
                                    ctx.arc(lastX, height - (height * (last.up / maxSpeed)), 3, 0, 2 * Math.PI)
                                    ctx.fill()
                                }
                            }

                            // Time labels
                            Item {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 20

                                Repeater {
                                    model: 5
                                    Text {
                                        text: {
                                            var now = new Date()
                                            var span = root.graphTimespan === 0 ? 300000 : root.graphTimespan * 60 * 1000
                                            var t = now.getTime() - span + (span / 4) * index
                                            var d = new Date(t)
                                            return d.getHours().toString().padStart(2, '0') + ":" + d.getMinutes().toString().padStart(2, '0')
                                        }
                                        font.pixelSize: fs(9)
                                        color: root.colorTextMuted
                                        x: (parent.width / 4) * index - width / 2
                                        anchors.bottom: parent.bottom
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // TORRENT TABLE
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: "Torrents Sonarr/Radarr"
                font.bold: true
                font.pixelSize: fs(13)
                color: root.colorText
            }

            ListView {
                id: torrentListView
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 100
                model: root.torrentRows
                spacing: 2
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                // Plasma-native scrollbar
                PlasmaComponents3.ScrollBar.vertical: PlasmaComponents3.ScrollBar {
                    id: torrentScrollBar
                    visible: torrentListView.contentHeight > torrentListView.height
                }

                delegate: Item {
                    width: torrentListView.width
                    height: 52

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: 6
                        color: Qt.rgba(0, 0, 0, 0.2)
                        border.color: Qt.rgba(root.colorAccentPurple.r, root.colorAccentPurple.g, root.colorAccentPurple.b, 0.3)
                        border.width: 0.5
                    }

                    Column {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 3

                        // Row 1: name + status — name takes available space, status right-aligned
                        Row {
                            width: parent.width
                            spacing: 8

                            Text {
                                text: modelData.name
                                font.pixelSize: fs(12)
                                font.bold: true
                                color: root.colorText
                                width: parent.width - statusTextLabel.width - 8
                                elide: Text.ElideRight
                            }
                            Text {
                                id: statusTextLabel
                                text: modelData.status
                                font.pixelSize: fs(10)
                                color: {
                                    var s = modelData.status
                                    if (s.includes("Baixando")) return root.colorDownload
                                    else if (s.includes("Enviando")) return root.colorUpload
                                    else if (s.includes("Pausado")) return root.colorWarning
                                    else return root.colorTextMuted
                                }
                                elide: Text.ElideRight
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        // Row 2: stats — evenly spaced, clipped to parent width
                        RowLayout {
                            width: parent.width
                            spacing: 8

                            Text {
                                text: modelData.progress + "%"
                                font.pixelSize: fs(10)
                                color: root.colorDownload
                            }
                            Text {
                                text: "⬇ " + modelData.downSpeed
                                font.pixelSize: fs(10)
                                color: root.colorDownload
                            }
                            Text {
                                text: "⬆ " + modelData.upSpeed
                                font.pixelSize: fs(10)
                                color: root.colorUpload
                            }
                            Text {
                                text: "ETA: " + modelData.eta
                                font.pixelSize: fs(10)
                                color: root.colorTextMuted
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignRight
                            }
                            Text {
                                id: peersText
                                text: "👥 " + modelData.peers
                                font.pixelSize: fs(10)
                                color: root.colorTextMuted
                            }
                        }
                    }
                }
            }

            // TOTAL ACCUMULATED STATS (all-time from Transmission)
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 56
                radius: 8
                color: Qt.rgba(0, 0, 0, 0.25)
                border.color: Qt.rgba(root.colorAccentPurple.r, root.colorAccentPurple.g, root.colorAccentPurple.b, 0.3)
                border.width: root.themedBorderWidth

                Row {
                    anchors.centerIn: parent
                    spacing: 20

                    Column {
                        spacing: 2

                        Text {
                            text: "⬇ Total"
                            font.pixelSize: fs(10)
                            color: root.colorTextMuted
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Text {
                            text: root.hasData ? formatBytes(root.sessionStats["cumulative-stats"] ? (root.sessionStats["cumulative-stats"].downloadedBytes || 0) : 0) : "--"
                            font.pixelSize: fs(14)
                            font.bold: true
                            font.family: "JetBrains Mono, Noto Sans Mono, monospace"
                            color: root.colorDownload
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }

                    Rectangle {
                        width: 1
                        height: 36
                        anchors.verticalCenter: parent.verticalCenter
                        color: Qt.rgba(root.colorAccentPurple.r, root.colorAccentPurple.g, root.colorAccentPurple.b, 0.3)
                    }

                    Column {
                        spacing: 2

                        Text {
                            text: "⬆ Total"
                            font.pixelSize: fs(10)
                            color: root.colorTextMuted
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Text {
                            text: root.hasData ? formatBytes(root.sessionStats["cumulative-stats"] ? (root.sessionStats["cumulative-stats"].uploadedBytes || 0) : 0) : "--"
                            font.pixelSize: fs(14)
                            font.bold: true
                            font.family: "JetBrains Mono, Noto Sans Mono, monospace"
                            color: root.colorUpload
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }
            }
        }
    }

    // ==========================================
    // RPC FUNCTIONS
    // ==========================================
    function makeRpcCall(method, args) {
        var host = plasmoid.configuration.trHost || "localhost"
        var port = plasmoid.configuration.trPort || 9091
        var user = plasmoid.configuration.trUser || ""
        var pass = plasmoid.configuration.trPass || ""
        var rpcPath = plasmoid.configuration.trRpcPath || "/transmission/rpc"
        var url = "http://" + host + ":" + port + rpcPath

        var xhr = new XMLHttpRequest()
        xhr.open("POST", url, false)
        xhr.setRequestHeader("Content-Type", "application/json")

        var auth = Qt.btoa(user + ":" + pass)
        xhr.setRequestHeader("Authorization", "Basic " + auth)

        if (root.sessionId) {
            xhr.setRequestHeader("X-Transmission-Session-Id", root.sessionId)
        }

        var body = JSON.stringify({method: method, arguments: args || {}})
        xhr.send(body)

        if (xhr.status === 409) {
            var newSessionId = xhr.getResponseHeader("X-Transmission-Session-Id")
            if (newSessionId) {
                root.sessionId = newSessionId
                xhr.open("POST", url, false)
                xhr.setRequestHeader("Content-Type", "application/json")
                xhr.setRequestHeader("Authorization", "Basic " + auth)
                xhr.setRequestHeader("X-Transmission-Session-Id", newSessionId)
                xhr.send(body)
            }
        }

        if (xhr.status !== 200) {
            var errorMsg = "HTTP " + xhr.status
            if (xhr.responseText) errorMsg += ": " + xhr.responseText
            throw new Error(errorMsg)
        }

        var response = JSON.parse(xhr.responseText)
        if (response.result !== "success") {
            throw new Error("RPC error: " + response.result)
        }
        if (xhr.getResponseHeader("X-Transmission-Session-Id")) {
            root.sessionId = xhr.getResponseHeader("X-Transmission-Session-Id")
        }
        return response.arguments
    }

    function fetchData() {
        try {
            var stats = makeRpcCall("session-stats", {})

            var torrentData = makeRpcCall("torrent-get", {
                fields: ["id", "name", "status", "downloadDir", "totalSize", "leftUntilDone", "rateDownload", "rateUpload", "uploadRatio", "eta", "peersConnected", "isFinished", "labels", "trackers"]
            })

            root.sessionStats = stats
            root.connected = true
            root.hasData = true

            if (torrentData.torrents) {
                var filtered = torrentData.torrents.filter(function(t) {
                    var labels = t.labels || []
                    return labels.some(function(l) {
                        var lower = l.toLowerCase()
                        return lower.includes("sonarr") || lower.includes("radarr")
                    })
                })
                root.torrents = filtered
            } else {
                root.torrents = []
            }

            // Update speed history
            var now = Date.now()
            var timeSpanMs = root.graphTimespan === 0 ? 0 : root.graphTimespan * 60 * 1000
            var downSpeed = stats.downloadSpeed || 0
            var upSpeed = stats.uploadSpeed || 0
            root.speedHistory.push({time: now, down: downSpeed, up: upSpeed})
            if (timeSpanMs > 0) {
                var cutoff = now - timeSpanMs
                root.speedHistory = root.speedHistory.filter(function(p) { return p.time > cutoff })
            } else {
                // Realtime mode — limit to maxHistoryPoints to avoid unbounded growth
                if (root.speedHistory.length > root.maxHistoryPoints) {
                    root.speedHistory = root.speedHistory.slice(-root.maxHistoryPoints)
                }
            }

            updateUI()
            // Canvas repaints handled in updateUI() with typeof checks

        } catch (e) {
            console.error("Fetch error:", e.message)
            root.connected = false
            root.hasData = false
            root.lastError = e.message
        }
    }

    function updateUI() {
        // Build torrent rows array for ListView binding (avoids cross-scope ID access)
        var rows = []
        if (root.torrents) {
            var statusMap = {
                0: "Pausado", 1: "Verificando", 2: "Baixando", 3: "Enviando",
                4: "Verificando", 5: "Pausado", 6: "Enfileirado"
            }
            root.torrents.forEach(function(t) {
                rows.push({
                    name: t.name.length > 45 ? t.name.substring(0, 42) + "..." : t.name,
                    status: statusMap[t.status] || "Desconhecido",
                    progress: t.totalSize > 0 ? ((t.totalSize - t.leftUntilDone) / t.totalSize * 100).toFixed(1) : "0.0",
                    downSpeed: formatSpeed(t.rateDownload || 0),
                    upSpeed: formatSpeed(t.rateUpload || 0),
                    eta: formatETA(t.eta || -1),
                    peers: t.peersConnected || 0
                })
            })
            var maxShown = plasmoid.configuration.maxTorrentsShown || 15
            if (rows.length > maxShown) rows = rows.slice(0, maxShown)
        }
        root.torrentRows = rows

        // Trigger canvas repaints via tick property
        // (IDs inside fullRepresentation are NOT visible from root JS — see Plasma 6 QML notes)
        root.paintTick = root.paintTick + 1
    }

    function getMaxSpeed() {
        if (root.speedHistory.length === 0) return 1000000
        var now = Date.now()
        var ts = root.graphTimespan
        if (ts === undefined || isNaN(ts)) ts = 5.0
        var timeSpanMs = ts === 0 ? 0 : ts * 60 * 1000
        var minTime = timeSpanMs === 0 ? 0 : (now - timeSpanMs)
        var pts = timeSpanMs === 0 ? root.speedHistory : root.speedHistory.filter(function(p) { return p.time >= minTime })
        if (pts.length === 0) return 1000000
        var maxDown = Math.max.apply(null, pts.map(function(p) { return p.down }))
        var maxUp = Math.max.apply(null, pts.map(function(p) { return p.up }))
        return Math.max(maxDown, maxUp, 1000) * 1.2
    }

    function formatSpeed(bytesPerSec) {
        if (!bytesPerSec || bytesPerSec < 0) return "0 B/s"
        var units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var i = 0
        var speed = bytesPerSec
        while (speed >= 1024 && i < units.length - 1) {
            speed /= 1024
            i++
        }
        return speed.toFixed(speed >= 100 || i === 0 ? 0 : 1) + " " + units[i]
    }

    function formatBytes(bytes) {
        if (!bytes || bytes < 0) return "0 B"
        var units = ["B", "KB", "MB", "GB", "TB"]
        var i = 0
        var val = bytes
        while (val >= 1024 && i < units.length - 1) {
            val /= 1024
            i++
        }
        return val.toFixed(val >= 100 || i === 0 ? 0 : 1) + " " + units[i]
    }

    function formatETA(seconds) {
        if (!seconds || seconds < 0 || seconds > 86400*365) return "∞"
        if (seconds < 60) return seconds + "s"
        if (seconds < 3600) return Math.floor(seconds/60) + "m"
        if (seconds < 86400) return Math.floor(seconds/3600) + "h"
        return Math.floor(seconds/86400) + "d"
    }

    // ==========================================
    // TIMERS
    // ==========================================
    Timer {
        id: updateTimer
        interval: plasmoid.configuration.powerSaveMode === true ? root.updateInterval * 4 : root.updateInterval
        running: true
        repeat: true
        onTriggered: fetchData()
    }

    Component.onCompleted: {
        // Belt-and-suspenders: garante remoção do fundo padrão também via plasmoid API
        plasmoid.backgroundHints = PlasmaCore.Types.NoBackground
        fetchData()
    }
}
