import QtQuick
import QtQuick.Effects
import Components

FocusScope { 
    id: appRoot

    signal navigateTo(string path, var params, var listState)
    signal goBack()

    property var navParams: ({})
    property var navListState: ({})
<<<<<<< Updated upstream
=======
    readonly property bool hiMdIconInHeader: true
    property var moduleEntries: []

    function listState() {
        return { currentIndex: menuList.currentIndex,
                 hiMdFirst: menuList.model.length > 0 && !!menuList.model[0].hiMd }
    }

    function updateMenu() {
        var index = menuList.currentIndex
        var oldRows = menuList.model
        var hadDisc = oldRows.length > 0 && !!oldRows[0].hiMd
        var rows = moduleEntries.slice()
        var disc = usbAutoPlayWatcher.hiMdDisc
        if (disc.filePath)
            rows.unshift({ name: disc.title, entry_point: "modules/local_files/views/Root.qml",
                        hiMd: true, params: { autoPlayPath: disc.filePath, title: disc.title,
                                             historyKey: disc.historyKey, hiMd: true, usbPlayback: true } })
        if (oldRows.length > 0 && hadDisc !== !!disc.filePath) {
            if (disc.filePath)
                index++
            else if (index > 0)
                index--
        }
        menuList.model = rows
        if (rows.length > 0) {
            menuList.currentIndex = Math.max(0, Math.min(index, rows.length - 1))
            menuList.positionViewAtIndex(menuList.currentIndex, ListView.Contain)
        }
    }
>>>>>>> Stashed changes

    Component.onCompleted: {
        appCore.scan_for_modules()
    }

    Connections {
        target: appCore;
        function onModulesLoaded(moduleData) {
            menuList.model = moduleData
            if (moduleData.length > 0) {
                var restore = (navListState.currentIndex !== undefined) ? navListState.currentIndex : 0
<<<<<<< Updated upstream
                menuList.currentIndex = Math.min(restore, moduleData.length - 1)
=======
                if (navListState.hiMdFirst !== undefined &&
                        navListState.hiMdFirst !== listState().hiMdFirst) {
                    if (listState().hiMdFirst)
                        restore++
                    else if (restore > 0)
                        restore--
                }
                menuList.currentIndex = Math.min(restore, menuList.count - 1)
>>>>>>> Stashed changes
                menuList.positionViewAtIndex(menuList.currentIndex, ListView.Contain)
            }
        }
    }

    // Header
    AppBar {
        indicateHiMdLoading: true
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: root.sh * 0.125 //60
        anchors.leftMargin: root.sw * 0.125 //80
    }

    // Empty state
    Column {
        anchors.centerIn: parent
        spacing: root.sh * 0.0333333 //16
        visible: menuList.count === 0
        Text {
            text: "No modules enabled"
            color: root.secondaryColor
            font.family: root.globalFont
            font.capitalization: Font.AllUppercase
            horizontalAlignment: Text.AlignHCenter
            anchors.horizontalCenter: parent.horizontalCenter
            font.pixelSize: root.sh * 0.05 //24
        }
        Text {
            text: "Please enable one in settings"
            color: root.tertiaryColor
            font.family: root.globalFont
            font.capitalization: Font.AllUppercase
            horizontalAlignment: Text.AlignHCenter
            anchors.horizontalCenter: parent.horizontalCenter
            font.pixelSize: root.sh * 0.0333333 //16
        }
    }

    ListView {
        id: menuList;
        objectName: "moduleMenu"
        model: [];
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: root.sh * 0.25 //120
        anchors.leftMargin: root.sw * 0.115625 //74
        width: root.sw * 0.76875 //492
        height: root.sh * 0.525 //252
        clip: true;
        focus: true;

        delegate: Item {
            width: menuList.width;
            height: root.sh * 0.0583333 //28

            Item {
                id: discIcon
                visible: !!modelData.hiMd
                width: visible ? root.sh * 0.05 : 0
                height: parent.height

                Rectangle {
                    anchors.fill: parent
                    color: root.accentColor
                    visible: menuList.currentIndex === index
                }

                Image {
                    id: discImage
                    objectName: modelData.hiMd ? "hiMdMenuImage" : ""
                    anchors.centerIn: parent
                    width: root.sh * 0.04
                    height: width
                    source: "../assets/images/logo.svg"
                    sourceSize.width: width
                    sourceSize.height: height
                    visible: false
                }
                MultiEffect {
                    objectName: modelData.hiMd ? "hiMdMenuIcon" : ""
                    anchors.fill: discImage
                    source: discImage
                    colorization: 1.0
                    colorizationColor: menuList.currentIndex === index ? root.surfaceColor : root.accentColor
                }
            }

            Item {
                id: textClipContainer;
                x: discIcon.width
                width: Math.min(rowText.implicitWidth, menuList.width - x);
                height: parent.height;
                clip: true;

                Rectangle {
                    color: root.accentColor;
                    anchors.fill: rowText;
                    visible: menuList.currentIndex === index;
                }

                Text {
                    id: rowText;
                    text: modelData.name;
                    color: menuList.currentIndex === index ? root.surfaceColor : root.primaryColor;
                    font.family: root.globalFont;
                    font.capitalization: Font.AllUppercase;
                    anchors.verticalCenter: parent.verticalCenter
                    x: 0
                    topPadding: root.sh * 0.0041667 //2
                    leftPadding: root.sw * 0.009375 //6
                    rightPadding: root.sw * 0.009375 //6
                    bottomPadding: root.sh * 0.00625 //3
                    font.pixelSize: root.sh * 0.05 //24
                }

                SequentialAnimation {
                    id: marqueeAnim;
                    running: (menuList.currentIndex === index) && (rowText.implicitWidth > textClipContainer.width);
                    loops: Animation.Infinite;

                    onRunningChanged: {
                        if (!running) rowText.x = 0;
                    }

                    PauseAnimation { 
                        duration: 1500;
                    }
                    
                    NumberAnimation {
                        target: rowText;
                        property: "x";
                        to: textClipContainer.width - rowText.implicitWidth;
                        duration: Math.abs(to) * 20;
                    }

                    PauseAnimation { 
                        duration: 2000;
                    }

                    PropertyAction { 
                        target: rowText; 
                        property: "x"; 
                        value: 0;
                    }
                }
            }
        }

        Keys.onUpPressed: {
            if (count === 0) return
            if (currentIndex > 0) currentIndex--
            else                  currentIndex = count - 1
            menuList.positionViewAtIndex(menuList.currentIndex, ListView.Contain)
        }
        Keys.onDownPressed: {
            if (count === 0) return
            if (currentIndex < count - 1) currentIndex++
            else                          currentIndex = 0
            menuList.positionViewAtIndex(menuList.currentIndex, ListView.Contain)
        }


        Keys.onReturnPressed: {
            // A row is {name, entry_point, params}. Module rows carry no params;
            // rows contributed by a backend (see AppCore::menuEntriesForModule) use
            // them to tell the module's router what was picked. This view stays
            // ignorant of what any of them mean.
            var row = menuList.model[menuList.currentIndex]
            if (!row) return
            console.log("Routing to: " + row.entry_point)
            appRoot.navigateTo(row.entry_point, row.params || {},
                               appRoot.listState())
        }

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace || event.key === Qt.Key_Back) {
                appRoot.navigateTo("views/Settings.qml", {}, appRoot.listState())
                event.accepted = true
            }
        }
    }

    // --- FOOTER ---
    Text {
        id: footer
        text: root.hints.back + ":SETTINGS " + root.hints.navigate + ":NAVIGATE " + root.hints.select + ":SELECT"
        color: root.tertiaryColor;
        font.family: root.globalFont;
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.bottomMargin: root.sh * 0.1041667 //50
        anchors.leftMargin: root.sw * 0.125 //80
        font.pixelSize: root.sh * 0.0333333 //16
    }
}