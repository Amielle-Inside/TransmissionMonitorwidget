1|import QtQuick
2|import QtQuick.Layouts
3|import QtQuick.Controls as QQC2
4|import org.kde.plasma.plasmoid
5|import org.kde.plasma.components 3.0 as PlasmaComponents3
6|import org.kde.plasma.extras as PlasmaExtras
7|import org.kde.plasma.core as PlasmaCore
8|import org.kde.kirigami 2.20 as Kirigami
9|
10|PlasmoidItem {
11|    id: root
12|
13|    // Desktop widget resize hints
14|    Layout.minimumWidth: Kirigami.Units.gridUnit * 30
15|    Layout.minimumHeight: Kirigami.Units.gridUnit * 40
16|    Layout.preferredWidth: Kirigami.Units.gridUnit * 40
17|    Layout.preferredHeight: Kirigami.Units.gridUnit * 55
18|
19|    // ==========================================
20|    // VISIBILITY & PERFORMANCE CONTROL
21|    // ==========================================
22|    property bool isActive: root.expanded || plasmoid.formFactor !== PlasmaCore.Types.Planar
23|    property bool _fetching: false
24|    property var lastPaintData: null
25|    property int lastPaintTime: 0
26|    property int paintThrottleMs: 1000
27|
28|    // Reactive config bindings with proper fallbacks
29|    property string widgetTitle: plasmoid.configuration.widgetTitle || "Transmission Monitor"
30|    property int updateInterval: plasmoid.configuration.updateInterval || 5000
31|    property bool powerSaveMode: plasmoid.configuration.powerSaveMode || false
32|    property bool showGraph: plasmoid.configuration.showGraph !== false
33|    // graphTimespan stored as int × 100 (e.g. 500 = 5.00 min). 0 = realtime/unlimited.
34|    property real graphTimespan: (plasmoid.configuration.graphTimespan !== undefined ? plasmoid.configuration.graphTimespan : 500) / 100.0
35|    property int transparency: plasmoid.configuration.transparency !== undefined ? plasmoid.configuration.transparency : 0
36|    property int themeIndex: plasmoid.configuration.themeIndex !== undefined ? plasmoid.configuration.themeIndex : 0
37|    property int maxTorrentsShown: plasmoid.configuration.maxTorrentsShown || 15
38|
39|    // State
40|    property var sessionStats: ({})
41|    property var torrents: []
42|    property var torrentRows: []
43|    property var speedHistory: []
44|    property string sessionId: ""
45|    property bool connected: false
46|    property bool hasData: false
47|    property string lastError: ""
48|    property int maxHistoryPoints: 300
49|
50|    // Graph cache properties
51|    property var cachedGraphData: null
52|    property int lastGraphUpdate: 0
53|    property var cachedTimeLabels: []
54|
55|    // Speed history management
56|    property int historyTrimIndex: 0
57|
58|    // Monotonically increasing tick used to trigger canvas repaints
59|    // from root scope (IDs inside fullRepresentation are NOT visible from root JS)
60|    property int paintTick: 0
61|
62|    // Computed opacity for backdrop
63|    property real backdropOpacity: transparency / 100.0 * 0.85 + 0.15
64|
65|    // Helper: should we repaint the graph?
66|    function shouldRepaint() {
67|        if (root.powerSaveMode) return false  // No repaints in power save mode
68|        var now = Date.now()
69|        if (now - root.lastPaintTime < root.paintThrottleMs) return false
70|        var current = { down: root.sessionStats.downloadSpeed || 0, up: root.sessionStats.uploadSpeed || 0 }
71|        if (root.lastPaintData &&
72|            Math.abs(current.down - root.lastPaintData.down) < 1024 &&
73|            Math.abs(current.up - root.lastPaintData.up) < 1024) return false
74|        root.lastPaintData = current
75|        root.lastPaintTime = now
76|        return true
77|    }
78|
79|    // ==========================================
80|    // COMPACT REPRESENTATION (Panel)
81|    // ==========================================
82|    compactRepresentation: Item {
83|        id: compactRep
84|        Layout.minimumWidth: Kirigami.Units.iconSizes.large
85|        Layout.minimumHeight: Kirigami.Units.iconSizes.large
86|        Layout.preferredWidth: Kirigami.Units.gridUnit * 15
87|        Layout.preferredHeight: Kirigami.Units.iconSizes.large
88|        Layout.margins: Kirigami.Units.smallSpacing
89|
90|        Row {
91|            anchors.centerIn: parent
92|            spacing: Kirigami.Units.smallSpacing
93|
94|            PlasmaComponents3.Label {
95|                id: compactDlText
96|                text: root.hasData ? "▼ " + formatSpeed(root.sessionStats.downloadSpeed || 0) : "▼ --"
97|                font.pixelSize: Kirigami.Units.fontSizes.small
98|                font.family: "JetBrains Mono, Noto Sans Mono, monospace"
99|                font.bold: true
100|                color: Kirigami.Theme.highlightColor
101|                verticalAlignment: Text.AlignVCenter
102|            }
103|
104|            PlasmaComponents3.Label {
105|                text: "│"
106|                font.pixelSize: Kirigami.Units.fontSizes.small
107|                color: Kirigami.Theme.textColor
108|                opacity: 0.5
109|                verticalAlignment: Text.AlignVCenter
110|            }
111|
112|            PlasmaComponents3.Label {
113|                id: compactUlText
114|                text: root.hasData ? "▲ " + formatSpeed(root.sessionStats.uploadSpeed || 0) : "▲ --"
115|                font.pixelSize: Kirigami.Units.fontSizes.small
116|                font.family: "JetBrains Mono, Noto Sans Mono, monospace"
117|                font.bold: true
118|                color: Kirigami.Theme.negativeTextColor
119|                verticalAlignment: Text.AlignVCenter
120|            }
121|        }
122|
123|        MouseArea {
124|            anchors.fill: parent
125|            onClicked: root.expanded = !root.expanded
126|            cursorShape: Qt.PointingHandCursor
127|        }
128|    }
129|
130|    // ==========================================
131|    // FULL REPRESENTATION (Popup)
132|    // ==========================================
133|    fullRepresentation: Item {
134|        id: fullRep
135|        Layout.minimumWidth: Kirigami.Units.gridUnit * 30
136|        Layout.minimumHeight: Kirigami.Units.gridUnit * 40
137|        Layout.preferredWidth: Kirigami.Units.gridUnit * 40
138|        Layout.preferredHeight: Kirigami.Units.gridUnit * 55
139|        Layout.maximumWidth: Kirigami.Units.gridUnit * 80
140|        Layout.maximumHeight: Kirigami.Units.gridUnit * 120
141|        clip: true
142|
143|        // Background using Plasma theme
144|        PlasmaComponents3.Frame {
145|            id: backdrop
146|            anchors.fill: parent
147|            // Use theme background with transparency
148|            background: Rectangle {
149|                anchors.fill: parent
150|                radius: Kirigami.Units.largeRadius
151|                color: Kirigami.Theme.backgroundColor
152|                opacity: root.backdropOpacity
153|                border.color: Kirigami.Theme.highlightColor
154|                border.width: 1
155|            }
156|        }
157|
158|        ColumnLayout {
159|            anchors.fill: parent
160|            anchors.margins: Kirigami.Units.largeSpacing
161|            spacing: Kirigami.Units.largeSpacing
162|
163|            // HEADER
164|            RowLayout {
165|                Layout.fillWidth: true
166|                spacing: Kirigami.Units.mediumSpacing
167|
168|                // App Icon using Kirigami.Icon
169|                Kirigami.Icon {
170|                    id: appIcon
171|                    source: "network-transmit-receive"
172|                    Layout.preferredWidth: Kirigami.Units.iconSizes.large
173|                    Layout.preferredHeight: Kirigami.Units.iconSizes.large
174|                    color: Kirigami.Theme.highlightColor
175|                }
176|
177|                PlasmaComponents3.Label {
178|                    id: titleLabel
179|                    text: root.widgetTitle
180|                    font: Kirigami.Theme.titleFont
181|                    color: Kirigami.Theme.highlightColor
182|                    elide: Text.ElideRight
183|                    Layout.fillWidth: true
184|                }
185|
186|                // Connection Status Badge
187|                PlasmaComponents3.Frame {
188|                    Layout.preferredHeight: Kirigami.Units.gridUnit * 3
189|                    background: Rectangle {
190|                        anchors.fill: parent
191|                        radius: Kirigami.Units.smallRadius
192|                        color: root.connected
193|                            ? Kirigami.Theme.positiveColor
194|                            : Kirigami.Theme.negativeColor
195|                        opacity: 0.15
196|                        border.color: root.connected
197|                            ? Kirigami.Theme.positiveColor
198|                            : Kirigami.Theme.negativeColor
199|                        border.width: 1
200|                    }
201|
202|                    PlasmaComponents3.Label {
203|                        id: statusText
204|                        anchors.centerIn: parent
205|                        text: root.connected ? qsTr("Conectado") : qsTr("Desconectado")
206|                        font.pixelSize: Kirigami.Units.fontSizes.small
207|                        font.bold: true
208|                        color: root.connected
209|                            ? Kirigami.Theme.positiveColor
210|                            : Kirigami.Theme.negativeColor
211|                        Layout.minimumWidth: implicitWidth + Kirigami.Units.mediumSpacing * 2
212|                    }
213|                }
214|            }
215|
216|            // QUICK STATS ROW - Using PlasmaComponents3.Card
217|            RowLayout {
218|                Layout.fillWidth: true
219|                spacing: Kirigami.Units.mediumSpacing
220|
221|                // Download Card
222|                PlasmaComponents3.Frame {
223|                    Layout.fillWidth: true
224|                    Layout.preferredHeight: Kirigami.Units.gridUnit * 9
225|
226|                    Column {
227|                        anchors.centerIn: parent
228|                        spacing: Kirigami.Units.smallSpacing
229|
230|                        PlasmaComponents3.Label {
231|                            text: qsTr("⬇ Download")
232|                            font.pixelSize: Kirigami.Units.fontSizes.small
233|                            color: Kirigami.Theme.textColor
234|                            opacity: 0.7
235|                            anchors.horizontalCenter: parent.horizontalCenter
236|                        }
237|
238|                        PlasmaComponents3.Label {
239|                            id: dlSpeedText
240|                            text: root.hasData ? formatSpeed(root.sessionStats.downloadSpeed || 0) : qsTr("-- B/s")
241|                            font: Kirigami.Theme.titleFont
243|                            font.family: "JetBrains Mono, Noto Sans Mono, monospace"
244|                            color: Kirigami.Theme.highlightColor
245|                            anchors.horizontalCenter: parent.horizontalCenter
246|                        }
247|
248|                        PlasmaComponents3.Label {
249|                            id: dlSessionText
250|                            text: qsTr("Sessão: ") + formatBytes(root.sessionStats["current-stats"] ? (root.sessionStats["current-stats"].downloadedBytes || 0) : 0)
251|                            font.pixelSize: Kirigami.Units.fontSizes.xSmall
252|                            color: Kirigami.Theme.textColor
253|                            opacity: 0.7
254|                            anchors.horizontalCenter: parent.horizontalCenter
255|                        }
256|                    }
257|                }
258|
259|                // Upload Card
260|                PlasmaComponents3.Frame {
261|                    Layout.fillWidth: true
262|                    Layout.preferredHeight: Kirigami.Units.gridUnit * 9
263|
264|                    Column {
265|                        anchors.centerIn: parent
266|                        spacing: Kirigami.Units.smallSpacing
267|
268|                        PlasmaComponents3.Label {
269|                            text: qsTr("⬆ Upload")
270|                            font.pixelSize: Kirigami.Units.fontSizes.small
271|                            color: Kirigami.Theme.textColor
272|                            opacity: 0.7
273|                            anchors.horizontalCenter: parent.horizontalCenter
274|                        }
275|
276|                        PlasmaComponents3.Label {
277|                            id: ulSpeedText
278|                            text: root.hasData ? formatSpeed(root.sessionStats.uploadSpeed || 0) : qsTr("-- B/s")
279|                            font: Kirigami.Theme.titleFont
281|                            font.family: "JetBrains Mono, Noto Sans Mono, monospace"
282|                            color: Kirigami.Theme.negativeTextColor
283|                            anchors.horizontalCenter: parent.horizontalCenter
284|                        }
285|
286|                        PlasmaComponents3.Label {
287|                            id: ulSessionText
288|                            text: qsTr("Sessão: ") + formatBytes(root.sessionStats["current-stats"] ? (root.sessionStats["current-stats"].uploadedBytes || 0) : 0)
289|                            font.pixelSize: Kirigami.Units.fontSizes.xSmall
290|                            color: Kirigami.Theme.textColor
291|                            opacity: 0.7
292|                            anchors.horizontalCenter: parent.horizontalCenter
293|                        }
294|                    }
295|                }
296|
297|                // Active Torrents Card
298|                PlasmaComponents3.Frame {
299|                    Layout.fillWidth: true
300|                    Layout.preferredHeight: Kirigami.Units.gridUnit * 9
301|
302|                    Column {
303|                        anchors.centerIn: parent
304|                        spacing: Kirigami.Units.smallSpacing
305|
306|                        PlasmaComponents3.Label {
307|                            text: qsTr("📦 Ativos")
308|                            font.pixelSize: Kirigami.Units.fontSizes.small
309|                            color: Kirigami.Theme.textColor
310|                            opacity: 0.7
311|                            anchors.horizontalCenter: parent.horizontalCenter
312|                        }
313|
314|                        PlasmaComponents3.Label {
315|                            id: activeCountText
316|                            text: root.torrents ? root.torrents.length : "0"
317|                            font: Kirigami.Theme.titleFont
319|                            font.pixelSize: Kirigami.Units.fontSizes.xLarge * 1.5
320|                            color: Kirigami.Theme.textColor
321|                            anchors.horizontalCenter: parent.horizontalCenter
322|                        }
323|
324|                        PlasmaComponents3.Label {
325|                            text: qsTr("torrents")
326|                            font.pixelSize: Kirigami.Units.fontSizes.xSmall
327|                            color: Kirigami.Theme.textColor
328|                            opacity: 0.7
329|                            anchors.horizontalCenter: parent.horizontalCenter
330|                        }
331|                    }
332|                }
333|            }
334|
335|            // GRAPH SECTION
336|            // GRAPH SECTION
337|            Rectangle {
338|                Layout.fillWidth: true
339|                height: 1
340|                color: Kirigami.Theme.textColor
341|                opacity: 0.15
342|                visible: root.showGraph
343|            }
344|
345|            PlasmaComponents3.Frame {
346|                id: graphCard
347|                Layout.fillWidth: true
348|                Layout.preferredHeight: Kirigami.Units.gridUnit * 22
349|                Layout.maximumHeight: Kirigami.Units.gridUnit * 25
350|                visible: root.showGraph
351|
352|                ColumnLayout {
353|                    anchors.fill: parent
354|                    anchors.margins: Kirigami.Units.mediumSpacing
355|                    spacing: Kirigami.Units.mediumSpacing
356|
357|                    // Graph Header
358|                    RowLayout {
359|                        Layout.fillWidth: true
360|                        spacing: Kirigami.Units.mediumSpacing
361|
362|                        PlasmaComponents3.Label {
363|                            text: root.graphTimespan === 0 ? qsTr("Velocidade (Tempo Real)") : qsTr("Velocidade (%1 min)").arg(root.graphTimespan.toFixed(2))
364|                            font: Kirigami.Theme.titleFont
366|                            color: Kirigami.Theme.textColor
367|                            Layout.fillWidth: true
368|                            elide: Text.ElideRight
369|                        }
370|
371|                        Row {
372|                            spacing: Kirigami.Units.smallSpacing
373|                            Layout.preferredHeight: Kirigami.Units.gridUnit * 3
374|
375|                            PlasmaComponents3.Label {
376|                                text: "▼"
377|                                font.pixelSize: Kirigami.Units.fontSizes.medium
378|                                color: Kirigami.Theme.highlightColor
379|                                anchors.verticalCenter: parent.verticalCenter
380|                            }
381|                            PlasmaComponents3.Label {
382|                                id: dlSpeedLabel
383|                                text: root.hasData ? formatSpeed(root.sessionStats.downloadSpeed || 0) : qsTr("-- B/s")
384|                                font.pixelSize: Kirigami.Units.fontSizes.medium
385|                                font.bold: true
386|                                font.family: "JetBrains Mono, Noto Sans Mono, monospace"
387|                                color: Kirigami.Theme.highlightColor
388|                                anchors.verticalCenter: parent.verticalCenter
389|                            }
390|                            PlasmaComponents3.Label {
391|                                text: "▲"
392|                                font.pixelSize: Kirigami.Units.fontSizes.medium
393|                                color: Kirigami.Theme.negativeTextColor
394|                                anchors.verticalCenter: parent.verticalCenter
395|                            }
396|                            PlasmaComponents3.Label {
397|                                id: ulSpeedLabel
398|                                text: root.hasData ? formatSpeed(root.sessionStats.uploadSpeed || 0) : qsTr("-- B/s")
399|                                font.pixelSize: Kirigami.Units.fontSizes.medium
400|                                font.bold: true
401|                                font.family: "JetBrains Mono, Noto Sans Mono, monospace"
402|                                color: Kirigami.Theme.negativeTextColor
403|                                anchors.verticalCenter: parent.verticalCenter
404|                            }
405|                        }
406|                    }
407|
408|                    // Chart Area
409|                    Item {
410|                        id: chartArea
411|                        Layout.fillWidth: true
412|                        Layout.fillHeight: true
413|                        Layout.minimumHeight: Kirigami.Units.gridUnit * 12
414|
415|                        // Y-axis labels
416|                        Item {
417|                            id: yAxisLabels
418|                            width: Kirigami.Units.gridUnit * 8
419|                            anchors.left: parent.left
420|                            anchors.top: parent.top
421|                            anchors.bottom: parent.bottom
422|                            anchors.bottomMargin: Kirigami.Units.gridUnit * 2
423|
424|                            Repeater {
425|                                model: 6
426|                                PlasmaComponents3.Label {
427|                                    text: {
428|                                        var maxSpeed = root.cachedGraphData ? root.cachedGraphData.maxSpeed : getMaxSpeed()
429|                                        return formatSpeed(maxSpeed - index * (maxSpeed / 5))
430|                                    }
431|                                    font.pixelSize: Kirigami.Units.fontSizes.xSmall
432|                                    font.bold: true
433|                                    y: (parent.height / 5) * index - height / 2
434|                                    anchors.right: parent.right
435|                                    anchors.rightMargin: Kirigami.Units.smallSpacing
436|                                    color: Kirigami.Theme.textColor
437|                                    opacity: 0.6
438|                                }
439|                            }
440|                        }
441|
442|                        // Chart Canvas Area
443|                        Item {
444|                            id: chartCanvasArea
445|                            anchors.left: yAxisLabels.right
446|                            anchors.right: parent.right
447|                            anchors.top: parent.top
448|                            anchors.bottom: parent.bottom
449|                            anchors.leftMargin: Kirigami.Units.mediumSpacing
450|                            anchors.bottomMargin: Kirigami.Units.gridUnit * 2
451|
452|                            // Grid Canvas
453|                            Canvas {
454|                                id: gridCanvas
455|                                anchors.fill: parent
456|                                onWidthChanged: requestPaint()
457|                                onHeightChanged: requestPaint()
458|                                onVisibleChanged: if (visible) requestPaint()
459|
460|                                Connections {
461|                                    target: root
462|                                    function onPaintTickChanged() { gridCanvas.requestPaint() }
463|                                }
464|
465|                                onPaint: {
466|                                    var ctx = getContext("2d")
467|                                    ctx.clearRect(0, 0, width, height)
468|                                    ctx.strokeStyle = Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.12)
469|                                    ctx.lineWidth = 1
470|
471|                                    // Horizontal grid lines
472|                                    for (var i = 0; i <= 5; i++) {
473|                                        var y = (height / 5) * i
474|                                        ctx.beginPath()
475|                                        ctx.moveTo(0, y)
476|                                        ctx.lineTo(width, y)
477|                                        ctx.stroke()
478|                                    }
479|
480|                                    // Vertical time divisions
481|                                    var timeDivs = root.graphTimespan === 0 ? 10 : root.graphTimespan * 2
482|                                    for (var i = 0; i <= timeDivs; i++) {
483|                                        var x = (width / timeDivs) * i
484|                                        ctx.beginPath()
485|                                        ctx.moveTo(x, 0)
486|                                        ctx.lineTo(x, height)
487|                                        ctx.stroke()
488|                                    }
489|                                }
490|                            }
491|
492|                            // Data Canvas
493|                            Canvas {
494|                                id: dataCanvas
495|                                anchors.fill: parent
496|                                onWidthChanged: requestPaint()
497|                                onHeightChanged: requestPaint()
498|                                onVisibleChanged: if (visible) requestPaint()
499|
500|                                Connections {
501|                                    target: root
502|                                    function onPaintTickChanged() { dataCanvas.requestPaint() }
503|                                }
504|
505|                                onPaint: {
506|                                    if (!root.shouldRepaint()) return
507|                                    var data = root.cachedGraphData
508|                                    if (!data || data.points.length < 2) return
509|                                    var ctx = getContext("2d")
510|                                    ctx.clearRect(0, 0, width, height)
511|
512|                                    // Colors from theme
513|                                    var dlColor = Kirigami.Theme.highlightColor
514|                                    var ulColor = Kirigami.Theme.negativeTextColor
515|                                    var dlFill = Qt.rgba(dlColor.r, dlColor.g, dlColor.b, 0.1)
516|                                    var ulFill = Qt.rgba(ulColor.r, ulColor.g, ulColor.b, 0.1)
517|
518|                                    // --- Fills first (behind lines) ---
519|                                    // Download fill
520|                                    ctx.fillStyle = dlFill
521|                                    ctx.beginPath()
522|                                    data.points.forEach(function(p, idx) {
523|                                        var x = p.x * width
524|                                        var y = height * p.yDown
525|                                        if (idx === 0) {
526|                                            ctx.moveTo(x, height)
527|                                            ctx.lineTo(x, y)
528|                                        } else {
529|                                            ctx.lineTo(x, y)
530|                                        }
531|                                    })
532|                                    ctx.lineTo(data.points[data.points.length - 1].x * width, height)
533|                                    ctx.lineTo(data.points[0].x * width, height)
534|                                    ctx.closePath()
535|                                    ctx.fill()
536|
537|                                    // Upload fill
538|                                    ctx.fillStyle = ulFill
539|                                    ctx.beginPath()
540|                                    data.points.forEach(function(p, idx) {
541|                                        var x = p.x * width
542|                                        var y = height * p.yUp
543|                                        if (idx === 0) {
544|                                            ctx.moveTo(x, height)
545|                                            ctx.lineTo(x, y)
546|                                        } else {
547|                                            ctx.lineTo(x, y)
548|                                        }
549|                                    })
550|                                    ctx.lineTo(data.points[data.points.length - 1].x * width, height)
551|                                    ctx.lineTo(data.points[0].x * width, height)
552|                                    ctx.closePath()
553|                                    ctx.fill()
554|
555|                                    // --- Lines on top of fills ---
556|                                    // Download line
557|                                    ctx.strokeStyle = dlColor
558|                                    ctx.lineWidth = 2.5
559|                                    ctx.lineCap = "round"
560|                                    ctx.lineJoin = "round"
561|                                    ctx.beginPath()
562|                                    data.points.forEach(function(p, idx) {
563|                                        var x = p.x * width
564|                                        var y = height * p.yDown
565|                                        if (idx === 0) ctx.moveTo(x, y)
566|                                        else ctx.lineTo(x, y)
567|                                    })
568|                                    ctx.stroke()
569|
570|                                    // Upload line
571|                                    ctx.strokeStyle = ulColor
572|                                    ctx.lineWidth = 2.5
573|                                    ctx.beginPath()
574|                                    data.points.forEach(function(p, idx) {
575|                                        var x = p.x * width
576|                                        var y = height * p.yUp
577|                                        if (idx === 0) ctx.moveTo(x, y)
578|                                        else ctx.lineTo(x, y)
579|                                    })
580|                                    ctx.stroke()
581|
582|                                    // Current value dots
583|                                    var last = data.points[data.points.length - 1]
584|                                    var lastX = last.x * width
585|
586|                                    ctx.fillStyle = dlColor
587|                                    ctx.beginPath()
588|                                    ctx.arc(lastX, height * last.yDown, 4, 0, 2 * Math.PI)
589|                                    ctx.fill()
590|
591|                                    ctx.fillStyle = ulColor
592|                                    ctx.beginPath()
593|                                    ctx.arc(lastX, height * last.yUp, 4, 0, 2 * Math.PI)
594|                                    ctx.fill()
595|                                }
596|                            }
597|
598|                            // Time labels (X-axis)
599|                            Item {
600|                                anchors.left: parent.left
601|                                anchors.right: parent.right
602|                                anchors.bottom: parent.bottom
603|                                height: Kirigami.Units.gridUnit * 2.5
604|
605|                                Repeater {
606|                                    model: 5
607|                                    PlasmaComponents3.Label {
608|                                        text: {
609|                                            return root.cachedTimeLabels[index] || "--:--"
610|                                        }
611|                                        font.pixelSize: Kirigami.Units.fontSizes.xSmall
612|                                        color: Kirigami.Theme.textColor
613|                                        opacity: 0.6
614|                                        x: (parent.width / 4) * index - width / 2
615|                                        anchors.bottom: parent.bottom
616|                                    }
617|                                }
618|                            }
619|                        }
620|                    }
621|                }
622|            }
623|
624|            // TORRENT LIST SECTION
625|            Rectangle {
626|                    Layout.fillWidth: true
627|                    height: 1
628|                    color: Kirigami.Theme.textColor
629|                    opacity: 0.15
630|                    radius: 0.5
631|                }
632|                Layout.fillWidth: true
633|            }
634|
635|            PlasmaComponents3.Label {
636|                Layout.fillWidth: true
637|                text: qsTr("Torrents Sonarr/Radarr")
638|                font: Kirigami.Theme.titleFont
640|                color: Kirigami.Theme.textColor
641|            }
642|
643|            ListView {
644|                id: torrentListView
645|                Layout.fillWidth: true
646|                Layout.fillHeight: true
647|                Layout.minimumHeight: Kirigami.Units.gridUnit * 12
648|                model: root.torrentRows
649|                spacing: Kirigami.Units.smallSpacing
650|                clip: true
651|                boundsBehavior: Flickable.StopAtBounds
652|
653|                // Plasma-native scrollbar
654|                PlasmaComponents3.ScrollBar.vertical: PlasmaComponents3.ScrollBar {
655|                    id: torrentScrollBar
656|                    visible: torrentListView.contentHeight > torrentListView.height
657|                }
658|
659|                delegate: PlasmaComponents3.Frame {
660|                    width: torrentListView.width
661|                    height: Kirigami.Units.gridUnit * 6.5
662|                    implicitHeight: Kirigami.Units.gridUnit * 6.5
663|
664|                    Column {
665|                        anchors.fill: parent
666|                        anchors.margins: Kirigami.Units.mediumSpacing
667|                        spacing: Kirigami.Units.smallSpacing
668|
669|                        // Row 1: name + status
670|                        Row {
671|                            width: parent.width
672|                            spacing: Kirigami.Units.mediumSpacing
673|
674|                            PlasmaComponents3.Label {
675|                                id: nameLabel
676|                                text: modelData.name
677|                                font.pixelSize: Kirigami.Units.fontSizes.medium
678|                                font.bold: true
679|                                color: Kirigami.Theme.textColor
680|                                Layout.fillWidth: true
681|                                elide: Text.ElideRight
682|                            }
683|
684|                            PlasmaComponents3.Label {
685|                                id: statusLabel
686|                                text: modelData.status
687|                                font.pixelSize: Kirigami.Units.fontSizes.small
688|                                color: {
689|                                    var s = modelData.status
690|                                    if (s.includes("Baixando")) return Kirigami.Theme.highlightColor
691|                                    else if (s.includes("Enviando")) return Kirigami.Theme.negativeTextColor
692|                                    else if (s.includes("Pausado")) return Kirigami.Theme.warningColor
693|                                    else return Kirigami.Theme.textColor
694|                                }
695|                                opacity: 0.8
696|                                elide: Text.ElideRight
697|                                anchors.verticalCenter: parent.verticalCenter
698|                            }
699|                        }
700|
701|                        // Row 2: stats
702|                        RowLayout {
703|                            width: parent.width
704|                            spacing: Kirigami.Units.mediumSpacing
705|
706|                            PlasmaComponents3.Label {
707|                                text: modelData.progress + "%"
708|                                font.pixelSize: Kirigami.Units.fontSizes.small
709|                                color: Kirigami.Theme.highlightColor
710|                            }
711|
712|                            PlasmaComponents3.Label {
713|                                text: "⬇ " + modelData.downSpeed
714|                                font.pixelSize: Kirigami.Units.fontSizes.small
715|                                color: Kirigami.Theme.highlightColor
716|                            }
717|
718|                            PlasmaComponents3.Label {
719|                                text: "⬆ " + modelData.upSpeed
720|                                font.pixelSize: Kirigami.Units.fontSizes.small
721|                                color: Kirigami.Theme.negativeTextColor
722|                            }
723|
724|                            PlasmaComponents3.Label {
725|                                text: "ETA: " + modelData.eta
726|                                font.pixelSize: Kirigami.Units.fontSizes.small
727|                                color: Kirigami.Theme.textColor
728|                                opacity: 0.7
729|                                elide: Text.ElideRight
730|                                Layout.fillWidth: true
731|                                horizontalAlignment: Text.AlignRight
732|                            }
733|
734|                            PlasmaComponents3.Label {
735|                                id: peersLabel
736|                                text: "👥 " + modelData.peers
737|                                font.pixelSize: Kirigami.Units.fontSizes.small
738|                                color: Kirigami.Theme.textColor
739|                                opacity: 0.7
740|                            }
741|                        }
742|                    }
743|                }
744|            }
745|
746|            // TOTAL ACCUMULATED STATS
747|            Rectangle {
748|                    Layout.fillWidth: true
749|            // TOTAL ACCUMULATED STATS
750|            Rectangle {
751|                Layout.fillWidth: true
752|                height: 1
753|                color: Kirigami.Theme.textColor
754|                opacity: 0.15
755|                visible: true
756|            }
757|            PlasmaComponents3.Frame {
758|                Layout.fillWidth: true
759|                Layout.preferredHeight: Kirigami.Units.gridUnit * 7
760|
761|                Row {
762|                    anchors.centerIn: parent
763|                    spacing: Kirigami.Units.largeSpacing
764|
765|                    Column {
766|                        spacing: Kirigami.Units.smallSpacing
767|
768|                        PlasmaComponents3.Label {
769|                            text: qsTr("⬇ Total")
770|                            font.pixelSize: Kirigami.Units.fontSizes.small
771|                            color: Kirigami.Theme.textColor
772|                            opacity: 0.7
773|                            anchors.horizontalCenter: parent.horizontalCenter
774|                        }
775|
776|                        PlasmaComponents3.Label {
777|                            text: root.hasData ? formatBytes(root.sessionStats["cumulative-stats"] ? (root.sessionStats["cumulative-stats"].downloadedBytes || 0) : 0) : qsTr("--")
778|                            font: Kirigami.Theme.titleFont
780|                            font.family: "JetBrains Mono, Noto Sans Mono, monospace"
781|                            color: Kirigami.Theme.highlightColor
782|                            anchors.horizontalCenter: parent.horizontalCenter
783|                        }
784|                    }
785|
786|                    Rectangle {
787|                        width: 1
788|                        Layout.fillHeight: true
789|                        color: Kirigami.Theme.highlightColor
790|                        opacity: 0.3
791|                    }
792|
793|                    Column {
794|                        spacing: Kirigami.Units.smallSpacing
795|
796|                        PlasmaComponents3.Label {
797|                            text: qsTr("⬆ Total")
798|                            font.pixelSize: Kirigami.Units.fontSizes.small
799|                            color: Kirigami.Theme.textColor
800|                            opacity: 0.7
801|                            anchors.horizontalCenter: parent.horizontalCenter
802|                        }
803|
804|                        PlasmaComponents3.Label {
805|                            text: root.hasData ? formatBytes(root.sessionStats["cumulative-stats"] ? (root.sessionStats["cumulative-stats"].uploadedBytes || 0) : 0) : qsTr("--")
806|                            font: Kirigami.Theme.titleFont
808|                            font.family: "JetBrains Mono, Noto Sans Mono, monospace"
809|                            color: Kirigami.Theme.negativeTextColor
810|                            anchors.horizontalCenter: parent.horizontalCenter
811|                        }
812|                    }
813|                }
814|            }
815|        }
816|    }
817|
818|    // ==========================================
819|    // RPC FUNCTIONS
820|    // ==========================================
821|    function buildRpcRequest(method, args) {
822|        var host = plasmoid.configuration.trHost || "localhost"
823|        var port = plasmoid.configuration.trPort || 9091
824|        var user = plasmoid.configuration.trUser || "Amielle"
825|        var pass = plasmoid.configuration.trPass || "NewsInside@15"
826|        var rpcPath = plasmoid.configuration.trRpcPath || "/transmission/rpc"
827|        var url = "http://" + host + ":" + port + rpcPath
828|        var auth = Qt.btoa(user + ":" + pass)
829|        return { url: url, auth: auth, body: JSON.stringify({method: method, arguments: args || {}}) }
830|    }
831|
832|    function sendRpcAsync(req, onSuccess, onError) {
833|        var xhr = new XMLHttpRequest()
834|        xhr.open("POST", req.url, true)  // ASYNC!
835|        xhr.setRequestHeader("Content-Type", "application/json")
836|        xhr.setRequestHeader("Authorization", "Basic " + req.auth)
837|        if (root.sessionId) {
838|            xhr.setRequestHeader("X-Transmission-Session-Id", root.sessionId)
839|        }
840|
841|        xhr.onload = function() {
842|            if (xhr.status === 409) {
843|                var newSid = xhr.getResponseHeader("X-Transmission-Session-Id")
844|                if (newSid) {
845|                    root.sessionId = newSid
846|                    // Retry once with new session ID
847|                    var retryXhr = new XMLHttpRequest()
848|                    retryXhr.open("POST", req.url, true)
849|                    retryXhr.setRequestHeader("Content-Type", "application/json")
850|                    retryXhr.setRequestHeader("Authorization", "Basic " + req.auth)
851|                    retryXhr.setRequestHeader("X-Transmission-Session-Id", newSid)
852|                    retryXhr.onload = function() {
853|                        handleRpcResponse(retryXhr, onSuccess, onError)
854|                    }
855|                    retryXhr.onerror = function() { onError(new Error("Network error on retry")) }
856|                    retryXhr.send(req.body)
857|                    return
858|                }
859|            }
860|            handleRpcResponse(xhr, onSuccess, onError)
861|        }
862|        xhr.onerror = function() { onError(new Error("Network error")) }
863|        xhr.send(req.body)
864|    }
865|
866|    function handleRpcResponse(xhr, onSuccess, onError) {
867|        if (xhr.status !== 200) {
868|            var errorMsg = "HTTP " + xhr.status
869|            if (xhr.responseText) errorMsg += ": " + xhr.responseText
870|            onError(new Error(errorMsg))
871|            return
872|        }
873|        try {
874|            var response = JSON.parse(xhr.responseText)
875|            if (response.result !== "success") {
876|                onError(new Error("RPC error: " + response.result))
877|                return
878|            }
879|            if (xhr.getResponseHeader("X-Transmission-Session-Id")) {
880|                root.sessionId = xhr.getResponseHeader("X-Transmission-Session-Id")
881|            }
882|            onSuccess(response.arguments)
883|        } catch (e) {
884|            onError(new Error("Parse error: " + e.message))
885|        }
886|    }
887|
888|    function fetchData() {
889|        if (root._fetching) return
890|        root._fetching = true
891|
892|        var req = buildRpcRequest("session-stats", {})
893|        sendRpcAsync(req, function(stats) {
894|            root.sessionStats = stats
895|            root.connected = true
896|            root.hasData = true
897|
898|            // Update speed history
899|            var now = Date.now()
900|            var timeSpanMs = root.graphTimespan === 0 ? 0 : root.graphTimespan * 60 * 1000
901|            var downSpeed = stats.downloadSpeed || 0
902|            var upSpeed = stats.uploadSpeed || 0
903|            root.speedHistory.push({time: now, down: downSpeed, up: upSpeed})
904|            if (timeSpanMs > 0) {
905|                var cutoff = now - timeSpanMs
906|                // In-place trim to avoid GC
907|                var i = 0
908|                while (i < root.speedHistory.length && root.speedHistory[i].time <= cutoff) i++
909|                if (i > 0) root.speedHistory.splice(0, i)
910|            } else {
911|                if (root.speedHistory.length > root.maxHistoryPoints) {
912|                    root.speedHistory.splice(0, root.speedHistory.length - root.maxHistoryPoints)
913|                }
914|            }
915|
916|            updateGraphCache()
917|            root.paintTick++
918|
919|            // Second request for torrents (parallel)
920|            var req2 = buildRpcRequest("torrent-get", {
921|                fields: ["id", "name", "status", "downloadDir", "totalSize", "leftUntilDone", "rateDownload", "rateUpload", "uploadRatio", "eta", "peersConnected", "isFinished", "labels", "trackers"]
922|            })
923|            sendRpcAsync(req2, function(torrentData) {
924|                if (torrentData.torrents) {
925|                    var filtered = torrentData.torrents.filter(function(t) {
926|                        var labels = t.labels || []
927|                        return labels.some(function(l) {
928|                            var lower = l.toLowerCase()
929|                            return lower.includes("sonarr") || lower.includes("radarr")
930|                        })
931|                    })
932|                    root.torrents = filtered
933|                } else {
934|                    root.torrents = []
935|                }
936|                updateUI()
937|                root._fetching = false
938|            }, function(e) {
939|                console.error("Fetch torrent error:", e.message)
940|                root.torrents = []
941|                updateUI()
942|                root._fetching = false
943|            })
944|        }, function(e) {
945|            console.error("Fetch stats error:", e.message)
946|            root.connected = false
947|            root.hasData = false
948|            root.lastError = e.message
949|            root._fetching = false
950|        })
951|    }
952|
953|    function updateUI() {
954|        // Build torrent rows array for ListView binding (avoids cross-scope ID access)
955|        var rows = []
956|        if (root.torrents) {
957|            var statusMap = {
958|                0: qsTr("Pausado"), 1: qsTr("Verificando"), 2: qsTr("Baixando"), 3: qsTr("Enviando"),
959|                4: qsTr("Verificando"), 5: qsTr("Pausado"), 6: qsTr("Enfileirado")
960|            }
961|            root.torrents.forEach(function(t) {
962|                rows.push({
963|                    name: t.name.length > 50 ? t.name.substring(0, 47) + "..." : t.name,
964|                    status: statusMap[t.status] || qsTr("Desconhecido"),
965|                    progress: t.totalSize > 0 ? ((t.totalSize - t.leftUntilDone) / t.totalSize * 100).toFixed(1) : "0.0",
966|                    downSpeed: formatSpeed(t.rateDownload || 0),
967|                    upSpeed: formatSpeed(t.rateUpload || 0),
968|                    eta: formatETA(t.eta || -1),
969|                    peers: t.peersConnected || 0
970|                })
971|            })
972|        }
973|        root.torrentRows = rows
974|
975|        // Trigger canvas repaints via tick property
976|        root.paintTick = root.paintTick + 1
977|    }
978|
979|    function getMaxSpeed() {
980|        if (root.speedHistory.length === 0) return 1000000
981|        var now = Date.now()
982|        var ts = root.graphTimespan
983|        if (ts === undefined || isNaN(ts)) ts = 5.0
984|        var timeSpanMs = ts === 0 ? 0 : ts * 60 * 1000
985|        var minTime = timeSpanMs === 0 ? 0 : (now - timeSpanMs)
986|        var pts = timeSpanMs === 0 ? root.speedHistory : root.speedHistory.filter(function(p) { return p.time >= minTime })
987|        if (pts.length === 0) return 1000000
988|        var maxDown = Math.max.apply(null, pts.map(function(p) { return p.down }))
989|        var maxUp = Math.max.apply(null, pts.map(function(p) { return p.up }))
990|        return Math.max(maxDown, maxUp, 1000) * 1.2
991|    }
992|
993|    function formatSpeed(bytesPerSec) {
994|        if (!bytesPerSec || bytesPerSec < 0) return "0 B/s"
995|        var units = ["B/s", "KB/s", "MB/s", "GB/s"]
996|        var i = 0
997|        var speed = bytesPerSec
998|        while (speed >= 1024 && i < units.length - 1) {
999|            speed /= 1024
1000|            i++
1001|        }
1002|        return speed.toFixed(speed >= 100 || i === 0 ? 0 : 1) + " " + units[i]
1003|    }
1004|
1005|    function formatBytes(bytes) {
1006|        if (!bytes || bytes < 0) return "0 B"
1007|        var units = ["B", "KB", "MB", "GB", "TB"]
1008|        var i = 0
1009|        var val = bytes
1010|        while (val >= 1024 && i < units.length - 1) {
1011|            val /= 1024
1012|            i++
1013|        }
1014|        return val.toFixed(val >= 100 || i === 0 ? 0 : 1) + " " + units[i]
1015|    }
1016|
1017|    function formatETA(seconds) {
1018|        if (!seconds || seconds < 0 || seconds > 86400*365) return qsTr("∞")
1019|        if (seconds < 60) return seconds + "s"
1020|        if (seconds < 3600) return Math.floor(seconds/60) + "m"
1021|        if (seconds < 86400) return Math.floor(seconds/3600) + "h"
1022|        return Math.floor(seconds/86400) + "d"
1023|    }
1024|
1025|    // ==========================================
1026|    // TIMERS
1027|    // ==========================================
1028|    Timer {
1029|        id: updateTimer
1030|        interval: root.updateInterval
1031|        running: root.isActive && root.connected && !root.powerSaveMode
1032|        repeat: true
1033|        onTriggered: fetchData()
1034|    }
1035|
1036|    Timer {
1037|        id: powerSaveTimer
1038|        interval: root.updateInterval * 3  // 3x slower in power save mode
1039|        running: root.isActive && root.connected && root.powerSaveMode
1040|        repeat: true
1041|        onTriggered: fetchData()
1042|    }
1043|
1044|    Component.onCompleted: {
1045|        fetchData()
1046|    }
1047|}