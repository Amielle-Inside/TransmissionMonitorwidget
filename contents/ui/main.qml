import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components 3.0 as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami 2.20 as Kirigami

PlasmoidItem {
    id: root

    // Desktop widget resize hints
    Layout.minimumWidth: Kirigami.Units.gridUnit * 30
    Layout.minimumHeight: Kirigami.Units.gridUnit * 40
    Layout.preferredWidth: Kirigami.Units.gridUnit * 40
    Layout.preferredHeight: Kirigami.Units.gridUnit * 55

    // Reactive config bindings with proper fallbacks
    property string widgetTitle: plasmoid.configuration.widgetTitle || "Transmission Monitor"
    property int updateInterval: plasmoid.configuration.updateInterval || 5000
    property bool showGraph: plasmoid.configuration.showGraph !== false
    // graphTimespan stored as int × 100 (e.g. 500 = 5.00 min). 0 = realtime/unlimited.
    property real graphTimespan: (plasmoid.configuration.graphTimespan !== undefined ? plasmoid.configuration.graphTimespan : 500) / 100.0
    property int transparency: plasmoid.configuration.transparency !== undefined ? plasmoid.configuration.transparency : 0
    property int themeIndex: plasmoid.configuration.themeIndex !== undefined ? plasmoid.configuration.themeIndex : 0

    // State
    property var sessionStats: ({})
    property var torrents: []
    property var torrentRows: []
    property var speedHistory: []
    property string sessionId: ""
    property bool connected: false
    property bool hasData: false
    property string lastError: ""
    property int maxHistoryPoints: 300

    // Monotonically increasing tick used to trigger canvas repaints
    // from root scope (IDs inside fullRepresentation are NOT visible from root JS)
    property int paintTick: 0

    // Computed opacity for backdrop
    property real backdropOpacity: transparency / 100.0 * 0.85 + 0.15

    // ==========================================
    // COMPACT REPRESENTATION (Panel)
    // ==========================================
    compactRepresentation: Item {
        id: compactRep
        Layout.minimumWidth: Kirigami.Units.iconSizes.large
        Layout.minimumHeight: Kirigami.Units.iconSizes.large
        Layout.preferredWidth: Kirigami.Units.gridUnit * 15
        Layout.preferredHeight: Kirigami.Units.iconSizes.large
        Layout.margins: Kirigami.Units.smallSpacing

        Row {
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.Label {
                id: compactDlText
                text: root.hasData ? "▼ " + formatSpeed(root.sessionStats.downloadSpeed || 0) : "▼ --"
                font.pixelSize: Kirigami.Units.fontSizes.small
                font.family: "JetBrains Mono, Noto Sans Mono, monospace"
                font.bold: true
                color: Kirigami.Theme.highlightColor
                verticalAlignment: Text.AlignVCenter
            }

            PlasmaComponents3.Label {
                text: "│"
                font.pixelSize: Kirigami.Units.fontSizes.small
                color: Kirigami.Theme.textColor
                opacity: 0.5
                verticalAlignment: Text.AlignVCenter
            }

            PlasmaComponents3.Label {
                id: compactUlText
                text: root.hasData ? "▲ " + formatSpeed(root.sessionStats.uploadSpeed || 0) : "▲ --"
                font.pixelSize: Kirigami.Units.fontSizes.small
                font.family: "JetBrains Mono, Noto Sans Mono, monospace"
                font.bold: true
                color: Kirigami.Theme.negativeTextColor
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
        Layout.minimumWidth: Kirigami.Units.gridUnit * 30
        Layout.minimumHeight: Kirigami.Units.gridUnit * 40
        Layout.preferredWidth: Kirigami.Units.gridUnit * 40
        Layout.preferredHeight: Kirigami.Units.gridUnit * 55
        Layout.maximumWidth: Kirigami.Units.gridUnit * 80
        Layout.maximumHeight: Kirigami.Units.gridUnit * 120
        clip: true

        // Background using Plasma theme
        PlasmaComponents3.Frame {
            id: backdrop
            anchors.fill: parent
            // Use theme background with transparency
            background: Rectangle {
                anchors.fill: parent
                radius: Kirigami.Units.largeRadius
                color: Kirigami.Theme.backgroundColor
                opacity: root.backdropOpacity
                border.color: Kirigami.Theme.highlightColor
                border.width: 1
                border.opacity: 0.3
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            // HEADER
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.mediumSpacing

                // App Icon using PlasmaComponents3.Icon
                PlasmaComponents3.Icon {
                    id: appIcon
                    source: "network-transmit-receive"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.large
                    Layout.preferredHeight: Kirigami.Units.iconSizes.large
                    color: Kirigami.Theme.highlightColor
                }

                PlasmaComponents3.Label {
                    id: titleLabel
                    text: root.widgetTitle
                    font: Kirigami.Theme.titleFont
                    font.bold: true
                    color: Kirigami.Theme.highlightColor
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                // Connection Status Badge
                PlasmaComponents3.Frame {
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                    background: Rectangle {
                        anchors.fill: parent
                        radius: Kirigami.Units.smallRadius
                        color: root.connected
                            ? Kirigami.Theme.positiveColor
                            : Kirigami.Theme.negativeColor
                        opacity: 0.15
                        border.color: root.connected
                            ? Kirigami.Theme.positiveColor
                            : Kirigami.Theme.negativeColor
                        border.width: 1
                    }

                    PlasmaComponents3.Label {
                        id: statusText
                        anchors.centerIn: parent
                        text: root.connected ? qsTr("Conectado") : qsTr("Desconectado")
                        font.pixelSize: Kirigami.Units.fontSizes.small
                        font.bold: true
                        color: root.connected
                            ? Kirigami.Theme.positiveColor
                            : Kirigami.Theme.negativeColor
                        Layout.minimumWidth: implicitWidth + Kirigami.Units.mediumSpacing * 2
                    }
                }
            }

            // QUICK STATS ROW - Using PlasmaComponents3.Card
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.mediumSpacing

                // Download Card
                PlasmaComponents3.Card {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 9

                    Column {
                        anchors.centerIn: parent
                        spacing: Kirigami.Units.smallSpacing

                        PlasmaComponents3.Label {
                            text: qsTr("⬇ Download")
                            font.pixelSize: Kirigami.Units.fontSizes.small
                            color: Kirigami.Theme.textColor
                            opacity: 0.7
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        PlasmaComponents3.Label {
                            id: dlSpeedText
                            text: root.hasData ? formatSpeed(root.sessionStats.downloadSpeed || 0) : qsTr("-- B/s")
                            font: Kirigami.Theme.titleFont
                            font.bold: true
                            font.family: "JetBrains Mono, Noto Sans Mono, monospace"
                            color: Kirigami.Theme.highlightColor
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        PlasmaComponents3.Label {
                            id: dlSessionText
                            text: qsTr("Sessão: ") + formatBytes(root.sessionStats["current-stats"] ? (root.sessionStats["current-stats"].downloadedBytes || 0) : 0)
                            font.pixelSize: Kirigami.Units.fontSizes.xSmall
                            color: Kirigami.Theme.textColor
                            opacity: 0.7
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }

                // Upload Card
                PlasmaComponents3.Card {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 9

                    Column {
                        anchors.centerIn: parent
                        spacing: Kirigami.Units.smallSpacing

                        PlasmaComponents3.Label {
                            text: qsTr("⬆ Upload")
                            font.pixelSize: Kirigami.Units.fontSizes.small
                            color: Kirigami.Theme.textColor
                            opacity: 0.7
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        PlasmaComponents3.Label {
                            id: ulSpeedText
                            text: root.hasData ? formatSpeed(root.sessionStats.uploadSpeed || 0) : qsTr("-- B/s")
                            font: Kirigami.Theme.titleFont
                            font.bold: true
                            font.family: "JetBrains Mono, Noto Sans Mono, monospace"
                            color: Kirigami.Theme.negativeTextColor
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        PlasmaComponents3.Label {
                            id: ulSessionText
                            text: qsTr("Sessão: ") + formatBytes(root.sessionStats["current-stats"] ? (root.sessionStats["current-stats"].uploadedBytes || 0) : 0)
                            font.pixelSize: Kirigami.Units.fontSizes.xSmall
                            color: Kirigami.Theme.textColor
                            opacity: 0.7
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }

                // Active Torrents Card
                PlasmaComponents3.Card {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 9

                    Column {
                        anchors.centerIn: parent
                        spacing: Kirigami.Units.smallSpacing

                        PlasmaComponents3.Label {
                            text: qsTr("📦 Ativos")
                            font.pixelSize: Kirigami.Units.fontSizes.small
                            color: Kirigami.Theme.textColor
                            opacity: 0.7
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        PlasmaComponents3.Label {
                            id: activeCountText
                            text: root.torrents ? root.torrents.length : "0"
                            font: Kirigami.Theme.titleFont
                            font.bold: true
                            font.pixelSize: Kirigami.Units.fontSizes.xLarge * 1.5
                            color: Kirigami.Theme.textColor
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        PlasmaComponents3.Label {
                            text: qsTr("torrents")
                            font.pixelSize: Kirigami.Units.fontSizes.xSmall
                            color: Kirigami.Theme.textColor
                            opacity: 0.7
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }
            }

            // GRAPH SECTION
            PlasmaComponents3.Separator {
                Layout.fillWidth: true
                visible: root.showGraph
            }

            PlasmaComponents3.Card {
                id: graphCard
                Layout.fillWidth: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 22
                Layout.maximumHeight: Kirigami.Units.gridUnit * 25
                visible: root.showGraph

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.mediumSpacing
                    spacing: Kirigami.Units.mediumSpacing

                    // Graph Header
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.mediumSpacing

                        PlasmaComponents3.Label {
                            text: root.graphTimespan === 0 ? qsTr("Velocidade (Tempo Real)") : qsTr("Velocidade (%1 min)").arg(root.graphTimespan.toFixed(2))
                            font: Kirigami.Theme.titleFont
                            font.bold: true
                            color: Kirigami.Theme.textColor
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        Row {
                            spacing: Kirigami.Units.smallSpacing
                            Layout.preferredHeight: Kirigami.Units.gridUnit * 3

                            PlasmaComponents3.Label {
                                text: "▼"
                                font.pixelSize: Kirigami.Units.fontSizes.medium
                                color: Kirigami.Theme.highlightColor
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            PlasmaComponents3.Label {
                                id: dlSpeedLabel
                                text: root.hasData ? formatSpeed(root.sessionStats.downloadSpeed || 0) : qsTr("-- B/s")
                                font.pixelSize: Kirigami.Units.fontSizes.medium
                                font.bold: true
                                font.family: "JetBrains Mono, Noto Sans Mono, monospace"
                                color: Kirigami.Theme.highlightColor
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            PlasmaComponents3.Label {
                                text: "▲"
                                font.pixelSize: Kirigami.Units.fontSizes.medium
                                color: Kirigami.Theme.negativeTextColor
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            PlasmaComponents3.Label {
                                id: ulSpeedLabel
                                text: root.hasData ? formatSpeed(root.sessionStats.uploadSpeed || 0) : qsTr("-- B/s")
                                font.pixelSize: Kirigami.Units.fontSizes.medium
                                font.bold: true
                                font.family: "JetBrains Mono, Noto Sans Mono, monospace"
                                color: Kirigami.Theme.negativeTextColor
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }

                    // Chart Area
                    Item {
                        id: chartArea
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: Kirigami.Units.gridUnit * 12

                        // Y-axis labels
                        Item {
                            id: yAxisLabels
                            width: Kirigami.Units.gridUnit * 8
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: Kirigami.Units.gridUnit * 2

                            Repeater {
                                model: 6
                                PlasmaComponents3.Label {
                                    text: {
                                        var maxSpeed = getMaxSpeed()
                                        return formatSpeed(maxSpeed - index * (maxSpeed / 5))
                                    }
                                    font.pixelSize: Kirigami.Units.fontSizes.xSmall
                                    font.bold: true
                                    y: (parent.height / 5) * index - height / 2
                                    anchors.right: parent.right
                                    anchors.rightMargin: Kirigami.Units.smallSpacing
                                    color: Kirigami.Theme.textColor
                                    opacity: 0.6
                                }
                            }
                        }

                        // Chart Canvas Area
                        Item {
                            id: chartCanvasArea
                            anchors.left: yAxisLabels.right
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: Kirigami.Units.mediumSpacing
                            anchors.bottomMargin: Kirigami.Units.gridUnit * 2

                            // Grid Canvas
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
                                    ctx.strokeStyle = Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.12)
                                    ctx.lineWidth = 1

                                    // Horizontal grid lines
                                    for (var i = 0; i <= 5; i++) {
                                        var y = (height / 5) * i
                                        ctx.beginPath()
                                        ctx.moveTo(0, y)
                                        ctx.lineTo(width, y)
                                        ctx.stroke()
                                    }

                                    // Vertical time divisions
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

                            // Data Canvas
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
                                    if (ts === undefined || isNaN(ts)) ts = 5.0
                                    var timeSpanMs = ts === 0 ? 0 : ts * 60 * 1000
                                    var minTime = timeSpanMs === 0 ? 0 : (now - timeSpanMs)

                                    var validPoints = timeSpanMs === 0 ? root.speedHistory : root.speedHistory.filter(function(p) { return p.time >= minTime })
                                    if (validPoints.length < 2) return

                                    var maxDown = Math.max.apply(null, validPoints.map(function(p) { return p.down }))
                                    var maxUp = Math.max.apply(null, validPoints.map(function(p) { return p.up }))
                                    var maxSpeed = Math.max(maxDown, maxUp, 1)
                                    maxSpeed = maxSpeed * 1.2

                                    var tMin = validPoints[0].time
                                    var tMax = validPoints[validPoints.length - 1].time
                                    var tRange = tMax - tMin
                                    if (tRange === 0) tRange = 1

                                    // Colors from theme
                                    var dlColor = Kirigami.Theme.highlightColor
                                    var ulColor = Kirigami.Theme.negativeTextColor
                                    var dlFill = Qt.rgba(dlColor.r, dlColor.g, dlColor.b, 0.1)
                                    var ulFill = Qt.rgba(ulColor.r, ulColor.g, ulColor.b, 0.1)

                                    // --- Fills first (behind lines) ---
                                    // Download fill
                                    ctx.fillStyle = dlFill
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

                                    // Upload fill
                                    ctx.fillStyle = ulFill
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
                                    ctx.strokeStyle = dlColor
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
                                    ctx.strokeStyle = ulColor
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

                                    ctx.fillStyle = dlColor
                                    ctx.beginPath()
                                    ctx.arc(lastX, height - (height * (last.down / maxSpeed)), 4, 0, 2 * Math.PI)
                                    ctx.fill()

                                    ctx.fillStyle = ulColor
                                    ctx.beginPath()
                                    ctx.arc(lastX, height - (height * (last.up / maxSpeed)), 4, 0, 2 * Math.PI)
                                    ctx.fill()
                                }
                            }

                            // Time labels (X-axis)
                            Item {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: Kirigami.Units.gridUnit * 2.5

                                Repeater {
                                    model: 5
                                    PlasmaComponents3.Label {
                                        text: {
                                            var now = new Date()
                                            var span = root.graphTimespan === 0 ? 300000 : root.graphTimespan * 60 * 1000
                                            var t = now.getTime() - span + (span / 4) * index
                                            var d = new Date(t)
                                            return d.getHours().toString().padStart(2, '0') + ":" + d.getMinutes().toString().padStart(2, '0')
                                        }
                                        font.pixelSize: Kirigami.Units.fontSizes.xSmall
                                        color: Kirigami.Theme.textColor
                                        opacity: 0.6
                                        x: (parent.width / 4) * index - width / 2
                                        anchors.bottom: parent.bottom
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // TORRENT LIST SECTION
            PlasmaComponents3.Separator {
                Layout.fillWidth: true
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: qsTr("Torrents Sonarr/Radarr")
                font: Kirigami.Theme.titleFont
                font.bold: true
                color: Kirigami.Theme.textColor
            }

            ListView {
                id: torrentListView
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: Kirigami.Units.gridUnit * 12
                model: root.torrentRows
                spacing: Kirigami.Units.smallSpacing
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                // Plasma-native scrollbar
                PlasmaComponents3.ScrollBar.vertical: PlasmaComponents3.ScrollBar {
                    id: torrentScrollBar
                    visible: torrentListView.contentHeight > torrentListView.height
                }

                delegate: PlasmaComponents3.Card {
                    width: torrentListView.width
                    height: Kirigami.Units.gridUnit * 6.5
                    implicitHeight: Kirigami.Units.gridUnit * 6.5

                    Column {
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.mediumSpacing
                        spacing: Kirigami.Units.smallSpacing

                        // Row 1: name + status
                        Row {
                            width: parent.width
                            spacing: Kirigami.Units.mediumSpacing

                            PlasmaComponents3.Label {
                                id: nameLabel
                                text: modelData.name
                                font.pixelSize: Kirigami.Units.fontSizes.medium
                                font.bold: true
                                color: Kirigami.Theme.textColor
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }

                            PlasmaComponents3.Label {
                                id: statusLabel
                                text: modelData.status
                                font.pixelSize: Kirigami.Units.fontSizes.small
                                color: {
                                    var s = modelData.status
                                    if (s.includes("Baixando")) return Kirigami.Theme.highlightColor
                                    else if (s.includes("Enviando")) return Kirigami.Theme.negativeTextColor
                                    else if (s.includes("Pausado")) return Kirigami.Theme.warningColor
                                    else return Kirigami.Theme.textColor
                                }
                                opacity: 0.8
                                elide: Text.ElideRight
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        // Row 2: stats
                        RowLayout {
                            width: parent.width
                            spacing: Kirigami.Units.mediumSpacing

                            PlasmaComponents3.Label {
                                text: modelData.progress + "%"
                                font.pixelSize: Kirigami.Units.fontSizes.small
                                color: Kirigami.Theme.highlightColor
                            }

                            PlasmaComponents3.Label {
                                text: "⬇ " + modelData.downSpeed
                                font.pixelSize: Kirigami.Units.fontSizes.small
                                color: Kirigami.Theme.highlightColor
                            }

                            PlasmaComponents3.Label {
                                text: "⬆ " + modelData.upSpeed
                                font.pixelSize: Kirigami.Units.fontSizes.small
                                color: Kirigami.Theme.negativeTextColor
                            }

                            PlasmaComponents3.Label {
                                text: "ETA: " + modelData.eta
                                font.pixelSize: Kirigami.Units.fontSizes.small
                                color: Kirigami.Theme.textColor
                                opacity: 0.7
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignRight
                            }

                            PlasmaComponents3.Label {
                                id: peersLabel
                                text: "👥 " + modelData.peers
                                font.pixelSize: Kirigami.Units.fontSizes.small
                                color: Kirigami.Theme.textColor
                                opacity: 0.7
                            }
                        }
                    }
                }
            }

            // TOTAL ACCUMULATED STATS
            PlasmaComponents3.Separator {
                Layout.fillWidth: true
            }

            PlasmaComponents3.Card {
                Layout.fillWidth: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 7

                Row {
                    anchors.centerIn: parent
                    spacing: Kirigami.Units.largeSpacing

                    Column {
                        spacing: Kirigami.Units.smallSpacing

                        PlasmaComponents3.Label {
                            text: qsTr("⬇ Total")
                            font.pixelSize: Kirigami.Units.fontSizes.small
                            color: Kirigami.Theme.textColor
                            opacity: 0.7
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        PlasmaComponents3.Label {
                            text: root.hasData ? formatBytes(root.sessionStats["cumulative-stats"] ? (root.sessionStats["cumulative-stats"].downloadedBytes || 0) : 0) : qsTr("--")
                            font: Kirigami.Theme.titleFont
                            font.bold: true
                            font.family: "JetBrains Mono, Noto Sans Mono, monospace"
                            color: Kirigami.Theme.highlightColor
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }

                    PlasmaComponents3.Separator {
                        orientation: Qt.Vertical
                        height: Kirigami.Units.gridUnit * 4.5
                        color: Kirigami.Theme.highlightColor
                        opacity: 0.3
                    }

                    Column {
                        spacing: Kirigami.Units.smallSpacing

                        PlasmaComponents3.Label {
                            text: qsTr("⬆ Total")
                            font.pixelSize: Kirigami.Units.fontSizes.small
                            color: Kirigami.Theme.textColor
                            opacity: 0.7
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        PlasmaComponents3.Label {
                            text: root.hasData ? formatBytes(root.sessionStats["cumulative-stats"] ? (root.sessionStats["cumulative-stats"].uploadedBytes || 0) : 0) : qsTr("--")
                            font: Kirigami.Theme.titleFont
                            font.bold: true
                            font.family: "JetBrains Mono, Noto Sans Mono, monospace"
                            color: Kirigami.Theme.negativeTextColor
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
        var user = plasmoid.configuration.trUser || "Amielle"
        var pass = plasmoid.configuration.trPass || "NewsInside@15"
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
                0: qsTr("Pausado"), 1: qsTr("Verificando"), 2: qsTr("Baixando"), 3: qsTr("Enviando"),
                4: qsTr("Verificando"), 5: qsTr("Pausado"), 6: qsTr("Enfileirado")
            }
            root.torrents.forEach(function(t) {
                rows.push({
                    name: t.name.length > 50 ? t.name.substring(0, 47) + "..." : t.name,
                    status: statusMap[t.status] || qsTr("Desconhecido"),
                    progress: t.totalSize > 0 ? ((t.totalSize - t.leftUntilDone) / t.totalSize * 100).toFixed(1) : "0.0",
                    downSpeed: formatSpeed(t.rateDownload || 0),
                    upSpeed: formatSpeed(t.rateUpload || 0),
                    eta: formatETA(t.eta || -1),
                    peers: t.peersConnected || 0
                })
            })
        }
        root.torrentRows = rows

        // Trigger canvas repaints via tick property
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
        if (!seconds || seconds < 0 || seconds > 86400*365) return qsTr("∞")
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
        interval: root.updateInterval
        running: true
        repeat: true
        onTriggered: fetchData()
    }

    Component.onCompleted: {
        fetchData()
    }
}