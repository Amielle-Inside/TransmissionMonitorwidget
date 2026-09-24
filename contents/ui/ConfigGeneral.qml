import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.components 3.0 as PlasmaComponents3

KCM.SimpleKCM {
    id: page

    // Property aliases binding to plasmoid.configuration.*
    property alias cfg_widgetTitle: widgetTitleField.text
    property alias cfg_updateInterval: updateIntervalSpinBox.value
    property alias cfg_showGraph: showGraphCheckBox.checked
    property alias cfg_graphTimespan: graphTimespanSpinBox.value
    property alias cfg_transparency: transparencySpinBox.value
    property alias cfg_themeIndex: themeComboBox.currentIndex
    property alias cfg_trHost: trHostField.text
    property alias cfg_trPort: trPortSpinBox.value
    property alias cfg_trUser: trUserField.text
    property alias cfg_trPass: trPassField.text
    property alias cfg_trRpcPath: trRpcPathField.text
    property alias cfg_powerSaveMode: powerSaveModeCheckBox.checked
    property alias cfg_maxTorrentsShown: maxTorrentsShownSpinBox.value
    property alias cfg_fontScale: fontScaleSpin.value
    property alias cfg_borderWidth: borderWidthSpin.value
    property alias cfg_cornerRadius: cornerRadiusSpin.value

    function cfgSetValue(key, value) {
        plasmoid.configuration[key] = value
    }


    property string testResultText: ""
    property color testResultColor: Kirigami.Theme.disabledTextColor

    Kirigami.FormLayout {
        anchors.fill: parent

        // Widget Title Section
        Kirigami.Separator {
            Kirigami.FormData.label: "Aparência"
            Kirigami.FormData.isSection: true
        }

        QQC2.TextField {
            id: widgetTitleField
            Kirigami.FormData.label: "Título do Widget:"
            placeholderText: "Transmission Monitor"
            text: "Transmission Monitor"

            Component.onCompleted: {
                text = cfg_widgetTitle || "Transmission Monitor"
            }
        }

        QQC2.ComboBox {
            id: themeComboBox
            Kirigami.FormData.label: "Tema do Widget:"
            model: ["Synthwave (Padrão)", "Leve (Transparente)", "Cyberpunk 2077", "Matrix", "AMOLED", "Personalizado"]
            currentIndex: cfg_themeIndex !== undefined ? cfg_themeIndex : 0
            onActivated: (index) => { cfg_themeIndex = index }

            // mantém sincronizado se mudar por fora
            onCurrentIndexChanged: {
                if (currentIndex !== cfg_themeIndex) cfg_themeIndex = currentIndex
            }
        }

        QQC2.SpinBox {
            id: fontScaleSpin
            Kirigami.FormData.label: "Tamanho da Fonte (%):"
            from: 80
            to: 140
            stepSize: 5
            value: cfg_fontScale !== undefined ? cfg_fontScale : 100
            onValueModified: cfg_fontScale = value
            textFromValue: function(value, locale) { return value + "%" }
            editable: true
        }

        QQC2.SpinBox {
            id: borderWidthSpin
            Kirigami.FormData.label: "Espessura da Borda (px):"
            from: 0
            to: 4
            value: cfg_borderWidth !== undefined ? cfg_borderWidth : 1
            onValueModified: cfg_borderWidth = value
        }

        QQC2.SpinBox {
            id: cornerRadiusSpin
            Kirigami.FormData.label: "Raio dos Cantos (px):"
            from: 0
            to: 24
            stepSize: 2
            value: cfg_cornerRadius !== undefined ? cfg_cornerRadius : 12
            onValueModified: cfg_cornerRadius = value
        }

        QQC2.SpinBox {
            id: transparencySpinBox
            Kirigami.FormData.label: "Transparência do Widget (0-100%):"
            from: 0
            to: 100
            value: 0
            stepSize: 5

            textFromValue: function(value, locale) {
                return value + "%"
            }

            valueFromText: function(text, locale) {
                return parseInt(text) || 0
            }

            Component.onCompleted: {
                value = cfg_transparency !== undefined ? cfg_transparency : 0
            }
        }

        QQC2.Label {
            text: "0% = Totalmente transparente (padrão, igual widgets nativos do Plasma)\n100% = Totalmente opaco"
            wrapMode: Text.WordWrap
            color: Kirigami.Theme.disabledTextColor
            Layout.fillWidth: true
        }

        // Graph Settings Section
        Kirigami.Separator {
            Kirigami.FormData.label: "Configurações do Gráfico"
            Kirigami.FormData.isSection: true
        }

        QQC2.CheckBox {
            id: showGraphCheckBox
            Kirigami.FormData.label: "Mostrar Gráfico de Velocidade:"
            checked: true

            Component.onCompleted: {
                checked = cfg_showGraph
            }
        }

        // Use real SpinBox with decimal support via from/to/stepSize × 100
        QQC2.SpinBox {
            id: graphTimespanSpinBox
            Kirigami.FormData.label: "Período do Gráfico (minutos):"
            // Store as integer × 100 to support decimals (0.05 granularity)
            from: 0
            to: 6000   // 60.00 min max
            value: 500  // 5.00 min default
            stepSize: 5 // 0.05 min per step
            // Display the real value with 2 decimal places
            textFromValue: function(value, locale) {
                var real = value / 100
                if (real === 0) return "0 (Tempo Real)"
                return real.toFixed(2) + " min"
            }
            valueFromText: function(text, locale) {
                // Strip non-numeric except dot
                var cleaned = text.replace(/[^0-9.]/g, "")
                var real = parseFloat(cleaned)
                if (isNaN(real)) return 500
                return Math.round(real * 100)
            }

            Component.onCompleted: {
                value = cfg_graphTimespan !== undefined ? cfg_graphTimespan : 500
            }
        }

        QQC2.Label {
            text: "0 = Tempo Real (sem limite, mostra todo o histórico disponível)\n0.05 a 60.00 min = janela fixa.\nIncrementos de 0.05 min (3 segundos)."
            wrapMode: Text.WordWrap
            color: Kirigami.Theme.disabledTextColor
            Layout.fillWidth: true
        }

        // General Settings Section
        Kirigami.Separator {
            Kirigami.FormData.label: "Configurações Gerais"
            Kirigami.FormData.isSection: true
        }

        QQC2.SpinBox {
            id: updateIntervalSpinBox
            Kirigami.FormData.label: "Intervalo de Atualização (ms):"
            from: 1000
            to: 60000
            value: 5000
            stepSize: 1000

            textFromValue: function(value, locale) {
                return (value / 1000).toFixed(1) + "s"
            }

            valueFromText: function(text, locale) {
                var seconds = parseFloat(text)
                return isNaN(seconds) ? 5000 : seconds * 1000
            }

            Component.onCompleted: {
                value = cfg_updateInterval
            }
        }

        QQC2.CheckBox {
            id: powerSaveModeCheckBox
            Kirigami.FormData.label: "Modo Econômico (4× menos updates, sem gráfico):"
        }

        QQC2.SpinBox {
            id: maxTorrentsShownSpinBox
            Kirigami.FormData.label: "Máx. torrents na lista:"
            from: 5
            to: 50
            stepSize: 5
        }


        // ==== Cores Personalizadas (visível só no tema Personalizado) ====
        Kirigami.Heading {
            level: 3
            text: "Cores Personalizadas (tema Personalizado)"
            visible: (cfg_themeIndex !== undefined ? cfg_themeIndex : 0) === 5
            Layout.fillWidth: true
            type: Kirigami.Heading.Type.Normal
        }

        Flow {
            visible: (cfg_themeIndex !== undefined ? cfg_themeIndex : 0) === 5
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Repeater {
                model: [
                    { key: "customBgStart", label: "Fundo (topo)", def: "#2a1b3d" },
                    { key: "customBgEnd", label: "Fundo (base)", def: "#1a0b2e" },
                    { key: "customAccent", label: "Acento 1", def: "#00e8ff" },
                    { key: "customAccent2", label: "Acento 2", def: "#ff75da" },
                    { key: "customDownload", label: "Download", def: "#3daee9" },
                    { key: "customUpload", label: "Upload", def: "#f05050" },
                    { key: "customText", label: "Texto", def: "#ffffff" },
                    { key: "customTextMuted", label: "Texto suave", def: "#a89fbb" },
                    { key: "customWarning", label: "Alerta", def: "#ffb84d" },
                    { key: "customCritical", label: "Crítico", def: "#ff4757" }
                ]
                delegate: ColumnLayout {
                    spacing: 2
                    QQC2.Label {
                        text: modelData.label
                        font.pixelSize: 10
                        color: Kirigami.Theme.disabledTextColor
                    }
                    RowLayout {
                        spacing: 4
                        Rectangle {
                            width: 22; height: 22
                            radius: 4
                            color: {
                                var v = plasmoid.configuration[modelData.key]
                                return /^#[0-9a-fA-F]{6}$/.test(v || "") ? v : modelData.def
                            }
                            border.width: 1
                            border.color: Kirigami.Theme.textColor
                        }
                        QQC2.TextField {
                            id: hexInput
                            Layout.preferredWidth: 82
                            font.family: "monospace"
                            text: {
                                var v = plasmoid.configuration[modelData.key]
                                return /^#[0-9a-fA-F]{6}$/.test(v || "") ? v : modelData.def
                            }
                            onEditingFinished: {
                                var t = text.trim()
                                if (/^#[0-9a-fA-F]{6}$/.test(t)) {
                                    // escreve via alias dinâmico
                                    cfgSetValue(modelData.key, t.toLowerCase())
                                } else {
                                    text = plasmoid.configuration[modelData.key] || modelData.def
                                }
                            }
                        }
                    }
                }
            }
        }
        // Transmission Connection Section
        Kirigami.Separator {
            Kirigami.FormData.label: "Conexão Transmission RPC"
            Kirigami.FormData.isSection: true
        }

        QQC2.TextField {
            id: trHostField
            Kirigami.FormData.label: "Host:"
            placeholderText: "localhost"
            text: "localhost"

            Component.onCompleted: {
                text = cfg_trHost || "localhost"
            }
        }

        QQC2.SpinBox {
            id: trPortSpinBox
            Kirigami.FormData.label: "Porta:"
            from: 1
            to: 65535
            value: 9091
            stepSize: 1

            Component.onCompleted: {
                value = cfg_trPort || 9091
            }
        }

        QQC2.TextField {
            id: trUserField
            Kirigami.FormData.label: "Usuário:"
            placeholderText: "transmission"
            text: ""

            Component.onCompleted: {
                text = cfg_trUser || ""
            }
        }

        QQC2.TextField {
            id: trPassField
            Kirigami.FormData.label: "Senha:"
            placeholderText: "sua_senha_aqui"
            echoMode: Text.Password

            Component.onCompleted: {
                text = cfg_trPass || ""
            }
        }

        QQC2.TextField {
            id: trRpcPathField
            Kirigami.FormData.label: "Caminho RPC:"
            placeholderText: "/transmission/rpc"
            text: "/transmission/rpc"

            Component.onCompleted: {
                text = cfg_trRpcPath || "/transmission/rpc"
            }
        }

        // Test Connection Button
        PlasmaComponents3.Button {
            Kirigami.FormData.label: ""
            Layout.fillWidth: true
            text: "Testar Conexão"
            icon.name: "network-connect"

            onClicked: {
                var result = testConnection()
                if (result.success) {
                    testResultText = "✅ Conectado com sucesso!"
                    testResultColor = Kirigami.Theme.positiveTextColor
                } else {
                    testResultText = "❌ Falhou: " + result.error
                    testResultColor = Kirigami.Theme.negativeTextColor
                }
            }
        }

        QQC2.Label {
            text: testResultText
            color: testResultColor
            visible: testResultText.length > 0
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        // Information Section
        Kirigami.Separator {
            Kirigami.FormData.label: "Informações"
            Kirigami.FormData.isSection: true
        }

        QQC2.Label {
            Kirigami.FormData.label: "Versão:"
            // metaData.version no Plasma 6; fallback para o valor do metadata.json
            text: (plasmoid.metaData && plasmoid.metaData.version) ? plasmoid.metaData.version : "2.0.0"
        }

        QQC2.Label {
            Kirigami.FormData.label: "Autor:"
            text: "Amielle"
        }

        QQC2.Label {
            text: "Monitor de velocidade Transmission com filtro Sonarr/Radarr.\nFiltrado por labels/categories: sonarr, radarr.\nConfiguração persistida via plasmoid.configuration (KPlugin)."
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            color: Kirigami.Theme.disabledTextColor
        }
    }

    function testConnection() {
        var host = trHostField.text || "localhost"
        var port = trPortSpinBox.value || 9091
        var user = trUserField.text || ""
        var pass = trPassField.text || ""
        var rpcPath = trRpcPathField.text || "/transmission/rpc"
        var url = "http://" + host + ":" + port + rpcPath

        var xhr = new XMLHttpRequest()
        var body = JSON.stringify({method: "session-stats", arguments: {}})
        var auth = user.length > 0 ? "Basic " + Qt.btoa(user + ":" + pass) : ""

        function send() {
            xhr.open("POST", url, false)
            xhr.setRequestHeader("Content-Type", "application/json")
            if (auth) xhr.setRequestHeader("Authorization", auth)
            xhr.send(body)
        }

        try {
            send()
            if (xhr.status === 409) {
                var sid = xhr.getResponseHeader("X-Transmission-Session-Id")
                if (sid) {
                    xhr.open("POST", url, false)
                    xhr.setRequestHeader("Content-Type", "application/json")
                    if (auth) xhr.setRequestHeader("Authorization", auth)
                    xhr.setRequestHeader("X-Transmission-Session-Id", sid)
                    xhr.send(body)
                }
            }
            if (xhr.status !== 200) return {success: false, error: "HTTP " + xhr.status}
            var response = JSON.parse(xhr.responseText)
            if (response.result !== "success") return {success: false, error: response.result}
            return {success: true}
        } catch (e) {
            return {success: false, error: e.message}
        }
    }
}