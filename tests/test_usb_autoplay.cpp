#include "../src/util/UsbAutoPlayWatcher.h"

#include <QCoreApplication>
#include <QFile>
#include <QDir>
#include <QTemporaryDir>

static bool writeFile(const QString &path, const QByteArray &contents)
{
    QFile file(path);
    return file.open(QIODevice::WriteOnly) && file.write(contents) == contents.size();
}

class UsbAutoPlayWatcherTest {
public:
    static int run()
    {
        QTemporaryDir directory;
        if (!directory.isValid())
            return 1;
        QFile marker(directory.filePath("Autoplay.txt"));
        QFile media(directory.filePath("video.mp4"));
        if (!marker.open(QIODevice::WriteOnly) || marker.write("video.mp4\n") < 0 ||
            !media.open(QIODevice::WriteOnly))
            return 2;
        marker.close();
        media.close();

        UsbAutoPlayWatcher watcher;
        int plays = 0;
        int removals = 0;
        QObject::connect(&watcher, &UsbAutoPlayWatcher::autoplayRequested,
                         [&plays](const QString &) { ++plays; });
        QObject::connect(&watcher, &UsbAutoPlayWatcher::driveRemoved,
                         [&removals] { ++removals; });

        const QList<QPair<QString, QString>> volumes = {{directory.path(), "/dev/test"}};
        const QSet<QString> connected = {"/dev/test"};
        watcher.processMountedVolumes(volumes, connected);
        watcher.processMountedVolumes(volumes, connected);
        if (plays != 1 || removals != 0)
            return 3;
        watcher.processMountedVolumes({}, {});
        if (plays != 1 || removals != 1)
            return 4;
        watcher.processMountedVolumes(volumes, connected);
        if (plays != 2 || removals != 1)
            return 5;

        if (!watcher.shouldAttemptMount("/dev/test"))
            return 6;
        watcher.m_attemptedPartitions.insert("/dev/test", watcher.m_elapsed.elapsed());
        if (watcher.shouldAttemptMount("/dev/test"))
            return 7;
        watcher.m_attemptedPartitions["/dev/test"] = watcher.m_elapsed.elapsed() - 10000;
        if (!watcher.shouldAttemptMount("/dev/test"))
            return 8;
        watcher.m_pendingPartitions.insert("/dev/test");
        if (watcher.shouldAttemptMount("/dev/test"))
            return 9;

        const QString usb = directory.filePath("usb-device");
        const QString block = usb + "/interface/host/block/sda";
        if (!QDir().mkpath(block) ||
            !writeFile(usb + "/idVendor", "054c\n") ||
            !writeFile(usb + "/product", "Hi-MD\n"))
            return 10;
        if (!UsbAutoPlayWatcher::isHiMdDevice(block) ||
            UsbAutoPlayWatcher::isHiMdDevice(directory.path()))
            return 11;
        if (!writeFile(usb + "/product", "Other USB drive\n") ||
            UsbAutoPlayWatcher::isHiMdDevice(block))
            return 12;

        UsbAutoPlayWatcher loading;
        int loadingChanges = 0;
        int errors = 0;
        QObject::connect(&loading, &UsbAutoPlayWatcher::hiMdLoadingChanged,
                         [&loadingChanges] { ++loadingChanges; });
        QObject::connect(&loading, &UsbAutoPlayWatcher::hiMdLoadError,
                         [&errors](const QString &) { ++errors; });
        loading.updateHiMdLoading({});
        if (loading.hiMdLoading() || loadingChanges != 0)
            return 13;
        loading.updateHiMdLoading(connected);
        loading.updateHiMdLoading(connected);
        if (!loading.hiMdLoading() || loadingChanges != 1)
            return 14;
        loading.processMountedVolumes(volumes, connected);
        if (loading.hiMdLoading() || loadingChanges != 2 || errors != 0)
            return 15;
        loading.updateHiMdLoading(connected);
        if (loading.hiMdLoading())
            return 16;
        loading.updateHiMdLoading({});
        loading.updateHiMdLoading(connected);
        if (!loading.hiMdLoading())
            return 17;
        loading.m_hiMdLoadingStarted = loading.m_elapsed.elapsed() - 60000;
        loading.updateHiMdLoading(connected);
        loading.updateHiMdLoading(connected);
        if (loading.hiMdLoading() || errors != 1)
            return 18;
        loading.updateHiMdLoading({});
        loading.updateHiMdLoading(connected);
        loading.updateHiMdLoading({});
        if (loading.hiMdLoading() || errors != 1)
            return 19;

        loading.processMountedVolumes({}, {});
        loading.updateHiMdLoading(connected);
        if (!QFile::remove(directory.filePath("Autoplay.txt")))
            return 20;
        loading.processMountedVolumes(volumes, connected);
        if (loading.hiMdLoading() || errors != 2)
            return 21;

        if (!writeFile(directory.filePath("Autoplay.txt"), "video.mp4\nTitle: Moana\n") ||
            !writeFile(directory.filePath("video.mp4"), "first video"))
            return 22;
        UsbAutoPlayWatcher discWatcher;
        discWatcher.m_hiMdDevices = connected;
        int discPlays = 0;
        int discChanges = 0;
        int discRemovals = 0;
        QObject::connect(&discWatcher, &UsbAutoPlayWatcher::hiMdAutoplayRequested,
                         [&discPlays](const QVariantMap &) { ++discPlays; });
        QObject::connect(&discWatcher, &UsbAutoPlayWatcher::hiMdDiscChanged,
                         [&discChanges] { ++discChanges; });
        QObject::connect(&discWatcher, &UsbAutoPlayWatcher::driveRemoved,
                         [&discRemovals] { ++discRemovals; });
        discWatcher.updateHiMdLoading(connected);
        discWatcher.processMountedVolumes(volumes, connected);
        const QVariantMap disc = discWatcher.hiMdDisc();
        const QString filePath = disc.value("filePath").toString();
        const QString historyKey = disc.value("historyKey").toString();
        if (discPlays != 1 || discChanges != 1 || filePath.isEmpty() ||
            disc.value("title").toString() != "Moana" || historyKey.isEmpty())
            return 23;
        discWatcher.processMountedVolumes(volumes, connected);
        if (discPlays != 1 || discChanges != 1)
            return 24;
        // Merely listing a disc must not claim playback or stop another player.
        discWatcher.updateHiMdLoading({});
        discWatcher.processMountedVolumes(volumes, connected);
        discWatcher.processMountedVolumes(volumes, connected);
        if (!discWatcher.hiMdDisc().isEmpty() || discRemovals != 0 || discPlays != 1)
            return 25;
        discWatcher.updateHiMdLoading(connected);
        discWatcher.processMountedVolumes(volumes, connected);
        if (discPlays != 2 || discWatcher.hiMdDisc().value("historyKey") != historyKey ||
            !discWatcher.activateHiMd(filePath) || discWatcher.activateHiMd("wrong"))
            return 26;
        discWatcher.updateHiMdLoading({});
        discWatcher.processMountedVolumes(volumes, connected);
        if (discRemovals != 1 || !discWatcher.hiMdDisc().isEmpty())
            return 27;
        discWatcher.updateHiMdLoading(connected);
        discWatcher.processMountedVolumes(volumes, connected);
        if (!discWatcher.activateHiMd(filePath))
            return 28;
        discWatcher.releasePlayback(filePath);
        discWatcher.processMountedVolumes(volumes, connected);
        discWatcher.updateHiMdLoading({});
        discWatcher.processMountedVolumes(volumes, connected);
        if (discPlays != 3 || discRemovals != 1)
            return 29;

        if (!writeFile(directory.filePath("video.mp4"), "other video"))
            return 30;
        const QVariantMap changed = discWatcher.autoplayFile(directory.path(), true);
        if (changed.value("historyKey").toString() == historyKey)
            return 31;
        QTemporaryDir otherMount;
        if (!otherMount.isValid() ||
            !writeFile(otherMount.filePath("video.mp4"), "first video") ||
            !writeFile(otherMount.filePath("Autoplay.txt"), "video.mp4\n"))
            return 32;
        const QVariantMap legacy = discWatcher.autoplayFile(otherMount.path(), true);
        if (legacy.value("title").toString() != "video.mp4" ||
            legacy.value("historyKey").toString() != historyKey)
            return 33;
        if (!writeFile(otherMount.filePath("Autoplay.txt"), "../video.mp4\nTitle: Bad\n") ||
            !discWatcher.autoplayFile(otherMount.path(), true).isEmpty() ||
            !writeFile(otherMount.filePath("Autoplay.txt"), "video.mp4\nTitle: \n") ||
            !discWatcher.autoplayFile(otherMount.path(), true).isEmpty() ||
            !writeFile(otherMount.filePath("Autoplay.txt"), "video.mp4\nTitle: A\nTitle: B\n") ||
            !discWatcher.autoplayFile(otherMount.path(), true).isEmpty())
            return 34;
        return 0;
    }
};

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    return UsbAutoPlayWatcherTest::run();
}
