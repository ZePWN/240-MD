"""Offscreen Hi-MD UI tests. Run with PySide6 installed."""

import os
from pathlib import Path
import unittest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
try:
    from PySide6.QtCore import QUrl, Qt
    from PySide6.QtGui import QGuiApplication
    from PySide6.QtQml import QQmlApplicationEngine
    from PySide6.QtTest import QTest
except ImportError:
    QGuiApplication = None


HARNESS = r"""
import QtQuick
import QtQuick.Window
Window {
    id: root
    width: 640; height: 480; visible: true
    property real sw: width
    property real sh: height
    property string globalFont: "Sans"
    property string primaryColor: "white"
    property string secondaryColor: "white"
    property string tertiaryColor: "white"
    property string surfaceColor: "black"
    property string accentColor: "white"
    property string appVersion: "test"
    property var hints: ({back:"B",navigate:"N",select:"S"})
    property bool usbPlaybackInProgress: false
    property string routed: ""
    property QtObject appCore: QtObject {
        signal modulesLoaded(var moduleData)
        signal appSettingChanged(string key, string value)
        property string resume: "ask"
        property string autoplay: "Off"
        property string appVersion: "test"
        function scan_for_modules() { modulesLoaded([]) }
        function get_settings() { return {app:{autoplay_md:autoplay}} }
        function getCustomColorSchemes() { return ({}) }
        function getCustomColorScheme() { return ({}) }
        function get_installed_modules() { return [] }
        function isAutostartSession() { return false }
        function startupModuleEntryPoint() { return "" }
        function localIpAddress() { return "" }
        function save_setting(id, key, value) { if (key === "autoplay_md") autoplay = value }
        function get_module_info(id) { return ({}) }
        function get_setting(id, key) {
            if (key === "resume_playback") return resume
            if (key === "autoplay_md") return autoplay
            return ""
        }
    }
    property QtObject usbAutoPlayWatcher: QtObject {
        signal autoplayRequested(string path)
        signal hiMdAutoplayRequested(var disc)
        signal hiMdLoadError(string message)
        signal driveRemoved()
        property var hiMdDisc: ({})
        property bool hiMdLoading: false
        property int activated: 0
        property int released: 0
        function activateHiMd(path) { activated++; return path === hiMdDisc.filePath }
        function releasePlayback(path) { released++ }
    }
    property QtObject localFilesBackend: QtObject {
        property string lastKey: ""
        property string savedKey: ""
        function isImage(path) { return false }
        function isPlaylist(path) { return false }
        function getSavedPosition(key) { lastKey = key; return {pos:42000, plPos:-1} }
        function savePosition(key, pos, plPos) { savedKey = key }
        function clearPosition(key) { savedKey = key }
    }
    property QtObject mpvController: QtObject {
        signal positionChanged(int ms)
        signal durationChanged(int ms)
        signal playlistPosChanged(int pos)
        signal playbackEnded(int pos, int duration, string reason)
        property real start: -1
        property int stops: 0
        function loadAndPlay(path, seconds) { start = seconds }
        function sendKey(key) {}
        function stop() { stops++ }
        function hasSmoothPlaybackTradeoff() { return false }
    }
    property QtObject inputManager: QtObject { property var hints: root.hints }
    property QtObject scriptsBackend: QtObject {
        signal scriptRunningChanged()
        property bool scriptBusy: false
    }
    property QtObject idleTracker: QtObject {
        property bool active: false
        property bool enabled: false
        property bool mpvActive: false
        property bool scriptActive: false
        property int threshold: 0
        function resetActivity() {}
    }
    property var mainWindow: null
    Loader {
        id: loader
        anchors.fill: parent
        focus: true
        onLoaded: item.forceActiveFocus()
        Connections {
            target: loader.item
            ignoreUnknownSignals: true
            function onNavigateTo(path, params, state) { root.routed = path }
            function onGoBack() { root.routed = "back" }
        }
    }
    function showMenu() { loader.setSource("views/ModuleList.qml") }
    function showSettings() { loader.setSource("views/Settings.qml") }
    function autoplayValue() {
        return loader.item.settingsItems.filter(function(row) { return row.key === "autoplay_md" })[0].value
    }
    function setDisc(present) {
        usbAutoPlayWatcher.hiMdDisc = present ? {filePath:"/disc/video.mp4",title:"Moana",historyKey:"hi-md:abc"} : ({})
    }
    function showPlayer(md, mode) {
        appCore.resume = mode
        loader.setSource("modules/local_files/views/Root.qml", {navParams: {
            autoPlayPath:"/disc/video.mp4", title:"Moana", historyKey:md ? "hi-md:abc" : "",
            hiMd:md, usbPlayback:true
        }})
    }
    function player() { return loader.item.children.filter(function(c) { return c.item !== undefined })[0].item }
    function doPlay() { player().play(42000, -1, false) }
    function endPlayback() { mpvController.playbackEnded(42000, 120000, "stopped") }
    function clear() { loader.source = "" }
    function showMain() {
        var component = Qt.createComponent("Main.qml")
        if (component.status !== Component.Ready) throw new Error(component.errorString())
        mainWindow = component.createObject(null)
    }
    function insert() { usbAutoPlayWatcher.hiMdAutoplayRequested(usbAutoPlayWatcher.hiMdDisc) }
    function setAutoplay(value) { appCore.autoplay = value }
    function setResume(value) { appCore.resume = value }
    function remove() { usbAutoPlayWatcher.driveRemoved() }
    function destroyMain() { mainWindow.destroy(); mainWindow = null }
}
"""


@unittest.skipIf(QGuiApplication is None, "PySide6 is required for Qt Quick tests")
class HiMdQmlTest(unittest.TestCase):
    def test_disc_menu_autoplay_and_resume(self):
        app = QGuiApplication.instance() or QGuiApplication([])
        repo = Path(__file__).resolve().parent.parent
        engine = QQmlApplicationEngine()
        engine.addImportPath(str(repo / "views"))
        engine.loadData(HARNESS.encode(), QUrl.fromLocalFile(str(repo / "__qml_test__.qml")))
        self.assertTrue(engine.rootObjects())
        root = engine.rootObjects()[0]
        watcher = root.property("usbAutoPlayWatcher")
        mpv = root.property("mpvController")
        backend = root.property("localFilesBackend")

        root.showMenu()
        app.processEvents()
        root.setDisc(True)
        app.processEvents()
        QTest.keyClick(root, Qt.Key.Key_Return)
        self.assertEqual(root.property("routed"), "modules/local_files/views/Root.qml")
        self.assertEqual(watcher.property("activated"), 1)
        root.setProperty("routed", "")
        root.setDisc(False)
        app.processEvents()
        QTest.keyClick(root, Qt.Key.Key_Return)
        self.assertEqual(root.property("routed"), "")

        root.showSettings()
        app.processEvents()
        self.assertEqual(root.autoplayValue(), "Off")
        QTest.keyClick(root, Qt.Key.Key_Down)
        QTest.keyClick(root, Qt.Key.Key_Down)
        QTest.keyClick(root, Qt.Key.Key_Right)
        app.processEvents()
        self.assertEqual(root.property("appCore").property("autoplay"), "On")
        root.showMenu()
        root.showSettings()
        self.assertEqual(root.autoplayValue(), "On")
        root.setAutoplay("")
        root.showMenu()
        root.showSettings()
        self.assertEqual(root.autoplayValue(), "On")
        root.setAutoplay("Off")

        root.setDisc(True)
        root.showMain()
        app.processEvents()
        activations = watcher.property("activated")
        root.insert()
        root.setAutoplay("On")
        app.processEvents()
        self.assertEqual(watcher.property("activated"), activations)
        root.insert()
        app.processEvents()
        self.assertEqual(watcher.property("activated"), activations + 1)
        stops = mpv.property("stops")
        root.remove()
        app.processEvents()
        self.assertEqual(mpv.property("stops"), stops)
        root.setResume("no")
        root.insert()
        app.processEvents()
        self.assertTrue(root.property("mainWindow").property("usbPlaybackInProgress"))
        root.remove()
        self.assertEqual(mpv.property("stops"), stops + 1)
        root.endPlayback()
        app.processEvents()
        self.assertEqual(backend.property("savedKey"), "hi-md:abc")
        root.destroyMain()
        app.processEvents()

        root.showPlayer(True, "ask")
        app.processEvents()
        self.assertTrue(root.player().property("overlayVisible"))
        root.doPlay()
        root.endPlayback()
        app.processEvents()
        self.assertEqual(backend.property("lastKey"), "hi-md:abc")
        self.assertEqual(backend.property("savedKey"), "hi-md:abc")
        root.clear()
        app.processEvents()
        root.showPlayer(True, "yes")
        app.processEvents()
        self.assertFalse(root.player().property("overlayVisible"))
        self.assertEqual(mpv.property("start"), 42)
        root.clear()
        app.processEvents()
        root.showPlayer(True, "no")
        app.processEvents()
        self.assertEqual(mpv.property("start"), 0)
        root.clear()
        app.processEvents()
        root.showPlayer(False, "ask")
        app.processEvents()
        self.assertFalse(root.player().property("overlayVisible"))
        self.assertEqual(mpv.property("start"), 0)
        root.clear()


if __name__ == "__main__":
    unittest.main()
