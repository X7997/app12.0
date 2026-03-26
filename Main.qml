/**
 * Main.qml - 主界面文件
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

Window {
    id: root
    width: 390
    height: 844
    visible: true
    color: "#F2F2F7"

    // ==================== 属性定义 ====================

    property string fixedPhoneNumber: "19731194079"
    property string currentLonLat: "等待数据接入"
    property string currentAddress: "正在获取终端位置..."
    property int connStatus: 0

    property string imgPhone: "qrc:/qt/qml/Iot/images/phone.png"
    property string imgSms: "qrc:/qt/qml/Iot/images/sms.png"
    property string imgEmergency: "qrc:/qt/qml/Iot/images/emergency.png"
    property string imgRefresh: "qrc:/qt/qml/Iot/images/refresh.png"
    property string imgCallIcon: "qrc:/qt/qml/Iot/images/hangout.png"
    property string imgSmsIcon: "qrc:/qt/qml/Iot/images/send.png"

    property string lastLonLat: "暂无历史数据"
    property string lastAddress: "暂无历史数据"
    property bool hasReceivedData: false
    property bool fallDetected: false

    property int currentPage: 0
    property int unreadCount: 0

    property int callStatus: 0
    property int smsStatus: 0

    property string customPhoneNumber: ""
    property string customSmsContent: ""

    property bool showCallDialog: false
    property bool showSmsDialog: false

    property bool isInCall: false
    property bool isNavigating: false

    // ==================== 数据模型 ====================

    ListModel { id: fallRecords }
    ListModel { id: chatRecords }

    // ==================== 信号处理 ====================

    onConnStatusChanged: {
        if (connStatus === 0) {
            statusIndicator.color = "#FF3B30"
        } else if (connStatus === 1) {
            statusIndicator.color = "#FF9500"
        } else if (connStatus === 2) {
            statusIndicator.color = "#34C759"
        }
    }

    Connections {
        target: typeof cloudManager !== "undefined" ? cloudManager : null
        ignoreUnknownSignals: true

        function onLocationUpdated(lonLat, address) {
            if (lonLat && lonLat.indexOf("暂无") === -1 && lonLat.indexOf("等待") === -1) {
                lastLonLat = currentLonLat
                lastAddress = currentAddress
                currentLonLat = lonLat
                currentAddress = address
                hasReceivedData = true
            }
        }

        function onConnectionStatusChanged(status) {
            connStatus = status
        }

        function onCommandResult(result) {}

        function onSerialDataReceived(data) {
            addChatMessage(data)
        }

        function onCallCompleted(success) {
            callStatus = 0
            isInCall = true
        }

        function onSmsCompleted(success) {
            smsStatus = 0
        }
    }

    // ==================== JavaScript函数与定时器 ====================

    function addChatMessage(message) {
        var timestamp = new Date().toLocaleTimeString("zh-CN")
        var msgText = message
        var isUser = false

        // 尝试解析 JSON 格式: {"role": "ai/user", "text": "消息内容"}
        try {
            var jsonData = JSON.parse(message)
            if (jsonData && jsonData.text) {
                msgText = jsonData.text
                isUser = (jsonData.role === "user")
            }
        } catch (e) {
            // 不是 JSON，按原来的逻辑处理
            isUser = message.indexOf("用户:") === 0 || message.indexOf("我:") === 0
        }

        chatRecords.append({
            "message": msgText,
            "time": timestamp,
            "isUser": isUser
        })

        // 自动滚动到底部
        if (chatRecords.count > 0) {
            chatListView.positionViewAtEnd()
        }
    }

    // 紧急报警自动挂断定时器 (5秒)
    Timer {
        id: emergencyAlertTimer
        interval: 5000
        onTriggered: {
            isInCall = false
        }
    }

    Timer {
        id: fallDetectTimer
        interval: 60000
        repeat: false
        onTriggered: {
            if (fallDetected) { emergencyCall() }
        }
    }

    function makeCustomCall() {
        if (customPhoneNumber.length > 0 && callStatus === 0) {
            callStatus = 1
            showCallDialog = false
            var jsonPayload = JSON.stringify({
                "type": "call",
                "phone": customPhoneNumber,
                "timestamp": new Date().toISOString()
            })
            if (typeof cloudManager !== "undefined") {
                cloudManager.sendCommand("call", jsonPayload)
            }
            isInCall = true
        }
    }

    function sendCustomSms() {
        if (customPhoneNumber.length > 0 && smsStatus === 0) {
            smsStatus = 1
            showSmsDialog = false
            var jsonPayload = JSON.stringify({
                "type": "sms",
                "phone": customPhoneNumber,
                "content": customSmsContent,
                "timestamp": new Date().toISOString()
            })
            if (typeof cloudManager !== "undefined") {
                cloudManager.sendCommand("sms", jsonPayload)
            }
        }
    }

    function emergencyCall() {
        fallDetected = true
        saveFallRecord()

        var sendLonLat = hasReceivedData ? currentLonLat : lastLonLat
        var sendAddress = hasReceivedData ? currentAddress : lastAddress
        var smsJson = JSON.stringify({
            "type": "sms",
            "phone": fixedPhoneNumber,
            "content": "【紧急求助】\n经纬度: " + sendLonLat + "\n地址: " + sendAddress,
            "emergency": true,
            "timestamp": new Date().toISOString()
        })
        if (typeof cloudManager !== "undefined") { cloudManager.sendCommand("sms", smsJson) }

        var callJson = JSON.stringify({
            "type": "call",
            "phone": fixedPhoneNumber,
            "emergency": true,
            "timestamp": new Date().toISOString()
        })
        if (typeof cloudManager !== "undefined") { cloudManager.sendCommand("call", callJson) }

        isInCall = true
        emergencyAlertTimer.start() // 5秒后自动关

        fallDetectTimer.start()
    }

    function saveFallRecord() {
        var timestamp = new Date().toLocaleString("zh-CN")
        var saveLonLat = hasReceivedData ? currentLonLat : lastLonLat
        var saveAddress = hasReceivedData ? currentAddress : lastAddress
        fallRecords.insert(0, {
            "time": timestamp,
            "lonLat": saveLonLat,
            "address": saveAddress,
            "alertTriggered": true
        })
        if (fallRecords.count > 10) { fallRecords.remove(10) }
    }

    // ==================== UI组件：顶部导航栏 ====================

    Rectangle {
        id: navBar
        width: parent.width
        height: root.height > 800 ? 94 : 74 
        color: "#F9F9F9" 
        opacity: 0.95
        z: 9

        // 极细的底部沉浸式分割线
        Rectangle {
            width: parent.width
            height: 0.5
            color: "#D1D1D6"
            anchors.bottom: parent.bottom
        }

        Row {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 12
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 6

            // 小圆点
            Rectangle {
                id: statusIndicator
                width: 6
                height: 6
                radius: 3
                color: connStatus === 2 ? "#34C759" : connStatus === 1 ? "#FF9500" : "#FF3B30"
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: currentPage === 0 ? "终端控制台" : "聊天记录"
                font.pixelSize: 17
                font.weight: Font.DemiBold
                color: "#000000"
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Image {
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 10
            width: 20
            height: 20
            source: imgRefresh
            fillMode: Image.PreserveAspectFit
            opacity: 0.8

            MouseArea {
                anchors.fill: parent
                anchors.margins: -10
                onClicked: {
                    if (hasReceivedData && typeof cloudManager !== "undefined") {
                        cloudManager.refreshLocation()
                    }
                }
            }
        }
    }

    // ==================== 主内容区 ====================

    Item {
        id: pageContent
        anchors.top: navBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: tabBar.top
        visible: !showCallDialog && !showSmsDialog

        Item {
            id: page1
            anchors.fill: parent
            visible: currentPage === 0

            ScrollView {
                anchors.fill: parent
                contentWidth: parent.width
                ScrollBar.vertical.policy: ScrollBar.AsNeeded

                ColumnLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 16

                    Item { Layout.preferredHeight: 4 }

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 180
                        Layout.preferredHeight: 30
                        radius: 15
                        color: "#E5E5EA"

                        Text {
                            text: hasReceivedData ? currentLonLat : "等待数据接入"
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            color: hasReceivedData ? "#1D1D1F" : "#8E8E93"
                            anchors.centerIn: parent
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 120
                        radius: 16
                        color: "#FFFFFF"

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 20
                            spacing: 8

                            Text {
                                text: "当前位置"
                                font.pixelSize: 13
                                font.weight: Font.Medium
                                color: "#86868B"
                            }

                            Text {
                                text: hasReceivedData ? currentAddress : lastAddress
                                font.pixelSize: 18
                                font.weight: Font.DemiBold
                                color: hasReceivedData ? "#1D1D1F" : "#C7C7CC"
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                verticalAlignment: Text.AlignTop
                                lineHeight: 1.2
                            }
                        }
                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 200
                        Layout.preferredHeight: 52
                        radius: 26
                        color: "#FF3B30"

                        Row {
                            anchors.centerIn: parent
                            spacing: 10

                            Image {
                                width: 20
                                height: 20
                                source: imgEmergency
                                fillMode: Image.PreserveAspectFit
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: "紧急求助"
                                font.pixelSize: 16
                                font.weight: Font.DemiBold
                                color: "#FFFFFF"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: emergencyCall()
                            onPressed: parent.opacity = 0.8
                            onReleased: parent.opacity = 1.0
                        }
                    }

                    Item { Layout.preferredHeight: 20 }

                    Row {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 16

                        Rectangle {
                            width: 150
                            height: 50
                            radius: 25
                            color: "#FFFFFF"

                            Row {
                                anchors.centerIn: parent
                                spacing: 6

                                Image {
                                    width: 18
                                    height: 18
                                    source: imgPhone
                                    fillMode: Image.PreserveAspectFit
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    text: callStatus === 1 ? "呼叫中..." : "语音呼叫"
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                    color: "#1D1D1F"
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: showCallDialog = true
                            }
                        }

                        Rectangle {
                            width: 150
                            height: 50
                            radius: 25
                            color: "#FFFFFF"

                            Row {
                                anchors.centerIn: parent
                                spacing: 6

                                Image {
                                    width: 18
                                    height: 18
                                    source: imgSms
                                    fillMode: Image.PreserveAspectFit
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    text: smsStatus === 1 ? "发送中..." : "发送短信"
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                    color: "#1D1D1F"
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: showSmsDialog = true
                            }
                        }
                    }

                    Item { Layout.preferredHeight: 20 }

                    Text {
                        text: "检测记录"
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        color: "#1D1D1F"
                        visible: fallRecords.count > 0
                        Layout.leftMargin: 4
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: fallRecords.count > 0 ? 200 : 0
                        radius: 16
                        color: "#FFFFFF"
                        visible: fallRecords.count > 0

                        ListView {
                            id: recordList
                            anchors.fill: parent
                            anchors.margins: 12
                            model: fallRecords
                            spacing: 10
                            clip: true
                            ScrollBar.vertical: ScrollBar { width: 4; policy: ScrollBar.AsNeeded }

                            delegate: Rectangle {
                                width: recordList.width
                                height: 75
                                radius: 10
                                color: "#F2F2F7"

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 4

                                    RowLayout {
                                        Layout.fillWidth: true

                                        Text {
                                            text: "第 " + (fallRecords.count - index) + " 次"
                                            font.pixelSize: 14
                                            font.weight: Font.Medium
                                            color: "#1D1D1F"
                                        }

                                        Item { Layout.fillWidth: true }

                                        Text {
                                            text: model.alertTriggered ? "已触发" : "完成"
                                            font.pixelSize: 12
                                            font.weight: Font.Medium
                                            color: model.alertTriggered ? "#FF3B30" : "#86868B"
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true

                                        Text {
                                            text: model.time
                                            font.pixelSize: 11
                                            color: "#8E8E93"
                                        }

                                        Item { Layout.fillWidth: true }

                                        Text {
                                            text: model.lonLat
                                            font.pixelSize: 11
                                            color: "#8E8E93"
                                        }
                                    }

                                    Text {
                                        text: model.address
                                        font.pixelSize: 11
                                        color: "#8E8E93"
                                        Layout.fillWidth: true
                                        maximumLineCount: 1
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }

                    Item { Layout.preferredHeight: 100 }
                }
            }
        }

        Item {
            id: page2
            anchors.fill: parent
            visible: currentPage === 1

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                ListView {
                    id: chatListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: chatRecords
                    spacing: 12
                    clip: true
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    Layout.margins: 16

                    delegate: Item {
                        width: chatListView.width - 32
                        height: messageBubble.height + 10

                        Rectangle {
                            id: messageBubble

                            anchors.right: model.isUser ? parent.right : undefined
                            anchors.left: model.isUser ? undefined : parent.left

                            width: Math.min(messageContent.implicitWidth + 24, parent.width * 0.75)
                            height: messageContent.implicitHeight + 24

                            radius: 12
                            color: model.isUser ? "#8E8E93" : "#FFFFFF" 

                            ColumnLayout {
                                id: messageContent
                                anchors.centerIn: parent
                                width: parent.width - 24
                                spacing: 4

                                Text {
                                    text: model.message
                                    font.pixelSize: 14
                                    color: model.isUser ? "#FFFFFF" : "#1D1D1F"
                                    wrapMode: Text.Wrap 
                                    Layout.fillWidth: true
                                }

                                Text {
                                    text: model.time
                                    font.pixelSize: 10
                                    color: model.isUser ? "rgba(255, 255, 255, 0.7)" : "#8E8E93"
                                    Layout.alignment: model.isUser ? Qt.AlignRight : Qt.AlignLeft
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ==================== UI组件：底部标签栏 ====================

    Rectangle {
        id: tabBar
        anchors.bottom: parent.bottom
        width: parent.width
        height: 80
        color: "#1C1C1E"
        z: 10

        Rectangle {
            anchors.top: parent.top
            width: parent.width
            height: 0.5
            color: "#38383A"
        }

        Row {
            anchors.centerIn: parent
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 25
            spacing: 100

            Rectangle {
                width: 80
                height: 44
                radius: 22
                color: currentPage === 0 ? "#2C2C2E" : "transparent"

                Text {
                    text: "控制台"
                    font.pixelSize: 14
                    font.weight: Font.Medium
                    color: currentPage === 0 ? "#FFFFFF" : "#8E8E93"
                    anchors.centerIn: parent
                }

                Behavior on color {
                    ColorAnimation { duration: 200 }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: currentPage = 0
                }
            }

            Rectangle {
                width: 80
                height: 44
                radius: 22
                color: currentPage === 1 ? "#2C2C2E" : "transparent"

                Rectangle {
                    visible: currentPage === 1 && unreadCount > 0
                    width: 8
                    height: 8
                    radius: 4
                    color: "#FF3B30"
                    anchors.horizontalCenterOffset: 20
                    anchors.top: parent.top
                    anchors.topMargin: 2
                }

                Text {
                    text: "聊天"
                    font.pixelSize: 14
                    font.weight: Font.Medium
                    color: currentPage === 1 ? "#FFFFFF" : "#8E8E93"
                    anchors.centerIn: parent
                }

                Behavior on color {
                    ColorAnimation { duration: 200 }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: currentPage = 1
                }
            }
        }
    }

    // ==================== 弹出对话框：打电话 ====================

    Rectangle {
        id: callDialog
        anchors.fill: parent
        color: "#80000000"
        visible: showCallDialog
        z: 100

        MouseArea {
            anchors.fill: parent
            onClicked: showCallDialog = false
        }

        Rectangle {
            width: Math.min(root.width - 60, 320)
            height: 250
            radius: 12
            color: "#FFFFFF"
            anchors.centerIn: parent

            MouseArea { anchors.fill: parent }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 30
                spacing: 10

                Text {
                    text: "拨打电话"
                    font.pixelSize: 22
                    font.family: "serif"
                    color: "#000000"
                    Layout.alignment: Qt.AlignHCenter
                    Layout.bottomMargin: 5
                }

                TextField {
                    id: callPhoneInput
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    placeholderText: "请输入您的电话号码"
                    placeholderTextColor: "#999999"
                    color: "#000000"
                    font.pixelSize: 13
                    text: customPhoneNumber
                    onTextChanged: customPhoneNumber = text

                    verticalAlignment: Text.AlignVCenter

                    background: Rectangle {
                        color: "transparent"
                        border.color: "#000000"
                        border.width: 1.5
                        radius: 10
                    }
                }

                Item { Layout.fillHeight: true }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    radius: 10
                    color: "#000000"

                    Text {
                        text: "呼叫"
                        font.pixelSize: 16
                        color: "#FFFFFF"
                        anchors.centerIn: parent
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: makeCustomCall()
                        onPressed: parent.opacity = 0.8
                        onReleased: parent.opacity = 1.0
                    }
                }

                Text {
                    text: "取消"
                    font.pixelSize: 13
                    color: "#666666"
                    Layout.alignment: Qt.AlignHCenter
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -10
                        onClicked: showCallDialog = false
                    }
                }
            }
        }
    }

    // ==================== 弹出对话框：发短信 ====================

    Rectangle {
        id: smsDialog
        anchors.fill: parent
        color: "#80000000"
        visible: showSmsDialog
        z: 100

        MouseArea {
            anchors.fill: parent
            onClicked: showSmsDialog = false
        }

        Rectangle {
            width: Math.min(root.width - 60, 320)
            height: 330
            radius: 12
            color: "#FFFFFF"
            anchors.centerIn: parent

            MouseArea { anchors.fill: parent }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 30
                spacing: 16

                Text {
                    text: "发送短信"
                    font.pixelSize: 22
                    font.family: "serif"
                    color: "#000000"
                    Layout.alignment: Qt.AlignHCenter
                    Layout.bottomMargin: 5
                }

                TextField {
                    id: smsPhoneInput
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    placeholderText: "请输入电话号码"
                    placeholderTextColor: "#999999"
                    font.pixelSize: 15
                    color: "#000000"
                    text: customPhoneNumber
                    onTextChanged: customPhoneNumber = text

                    verticalAlignment: Text.AlignVCenter

                    background: Rectangle {
                        color: "transparent"
                        border.color: "#000000"
                        border.width: 1.5
                        radius: 10
                    }
                }

                TextField {
                    id: smsContentInput
                    Layout.fillWidth: true
                    Layout.preferredHeight: 60
                    placeholderText: "请输入短信内容"
                    placeholderTextColor: "#999999"
                    font.pixelSize: 15
                    color: "#000000"
                    text: customSmsContent
                    onTextChanged: customSmsContent = text

                    verticalAlignment: Text.AlignVCenter

                    background: Rectangle {
                        color: "transparent"
                        border.color: "#E5E5EA"
                        border.width: 1.5
                        radius: 10
                    }
                }

                Item { Layout.fillHeight: true }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    radius: 10
                    color: "#000000"

                    Text {
                        text: "发送"
                        font.pixelSize: 16
                        color: "#FFFFFF"
                        anchors.centerIn: parent
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: sendCustomSms()
                        onPressed: parent.opacity = 0.8
                        onReleased: parent.opacity = 1.0
                    }
                }

                Text {
                    text: "取消"
                    font.pixelSize: 13
                    color: "#666666"
                    Layout.alignment: Qt.AlignHCenter
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -10
                        onClicked: showSmsDialog = false
                    }
                }
            }
        }
    }
}
