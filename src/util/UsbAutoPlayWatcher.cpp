#include "UsbAutoPlayWatcher.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QStorageInfo>

#include <cerrno>

UsbAutoPlayWatcher::UsbAutoPlayWatcher(QObject *parent)
    : QObject(parent)
{
    m_pollTimer.setInterval(1000);
    connect(&m_pollTimer, &QTimer::timeout, this, &UsbAutoPlayWatcher::scan);
}

void UsbAutoPlayWatcher::start()
{
    scan();
    m_pollTimer.start();
}

QString UsbAutoPlayWatcher::autoplayFile(const QString &mountPoint) const
{
    QFile marker(QDir(mountPoint).filePath(QStringLiteral("Autoplay.txt")));
    if (!marker.open(QIODevice::ReadOnly | QIODevice::Text))
        return {};

    const QString fileName = QString::fromUtf8(marker.readAll()).trimmed();
    if (fileName.isEmpty() || fileName == QStringLiteral(".") ||
        fileName == QStringLiteral("..") || fileName.contains('/') ||
        fileName.contains('\\'))
        return {};

    const QString canonicalMount = QFileInfo(mountPoint).canonicalFilePath();
    const QFileInfo mediaFile(QDir(mountPoint).filePath(fileName));
    const QString canonicalFile = mediaFile.canonicalFilePath();
    if (canonicalMount.isEmpty() || canonicalFile.isEmpty() || !mediaFile.isFile() ||
        QFileInfo(canonicalFile).path() != canonicalMount)
        return {};

    return canonicalFile;
}

void UsbAutoPlayWatcher::mountPartition(const QString &devicePath)
{
    m_attemptedPartitions.insert(devicePath);
    m_pendingPartitions.insert(devicePath);

    auto *process = new QProcess(this);
    connect(process, qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this, [this, process, devicePath](int exitCode, QProcess::ExitStatus status) {
        m_pendingPartitions.remove(devicePath);
        const QByteArray output = process->readAllStandardOutput().trimmed();
        const QByteArray error = process->readAllStandardError().trimmed();
        if (status != QProcess::NormalExit || exitCode != 0) {
            qWarning("[UsbAutoPlay] could not mount %s: %s",
                     qPrintable(devicePath), error.isEmpty() ? output.constData() : error.constData());
        } else {
            qInfo("[UsbAutoPlay] mounted %s", qPrintable(devicePath));
        }
        process->deleteLater();
        scan();
    });
    connect(process, &QProcess::errorOccurred, this,
            [this, process, devicePath](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;
        m_pendingPartitions.remove(devicePath);
        qWarning("[UsbAutoPlay] could not start udisksctl for %s: %s",
                 qPrintable(devicePath), qPrintable(process->errorString()));
        process->deleteLater();
    });
    process->start(QStringLiteral("udisksctl"), {
        QStringLiteral("mount"), QStringLiteral("--no-user-interaction"),
        QStringLiteral("--block-device"), devicePath
    });
}

void UsbAutoPlayWatcher::scan()
{
    const QString rootDevice = QString::fromLocal8Bit(QStorageInfo::root().device());
    QString rootDisk;
    if (!rootDevice.isEmpty()) {
        const QString canonicalRootDevice = QFileInfo(rootDevice).canonicalFilePath();
        const QString rootName = QFileInfo(canonicalRootDevice.isEmpty()
                                           ? rootDevice : canonicalRootDevice).fileName();
        const QString rootSysPath = QFileInfo(QStringLiteral("/sys/class/block/") + rootName)
                                        .canonicalFilePath();
        if (!rootSysPath.isEmpty()) {
            rootDisk = QFileInfo(rootSysPath).fileName();
            if (QFileInfo(rootSysPath + QStringLiteral("/partition")).exists())
                rootDisk = QFileInfo(rootSysPath).dir().dirName();
        }
    }

    QSet<QString> connectedNow;
    const QFileInfoList blockEntries = QDir(QStringLiteral("/sys/class/block"))
                                          .entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QFileInfo &entry : blockEntries) {
        const QString sysPath = entry.canonicalFilePath();
        if (sysPath.isEmpty() || !sysPath.contains(QStringLiteral("/usb")))
            continue;

        const bool isPartition = QFileInfo(entry.filePath() + QStringLiteral("/partition")).exists();
        if (!isPartition) {
            bool hasPartitions = false;
            const QFileInfoList children = QDir(sysPath).entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);
            for (const QFileInfo &child : children) {
                if (QFileInfo(child.filePath() + QStringLiteral("/partition")).exists()) {
                    hasPartitions = true;
                    break;
                }
            }
            if (hasPartitions)
                continue;
        }

        const QString diskName = isPartition ? QFileInfo(sysPath).dir().dirName()
                                             : QFileInfo(sysPath).fileName();
        if (!rootDisk.isEmpty() && diskName == rootDisk)
            continue;

        const QString devicePath = QStringLiteral("/dev/") + entry.fileName();
        connectedNow.insert(devicePath);

        bool alreadyMounted = false;
        for (const QStorageInfo &volume : QStorageInfo::mountedVolumes()) {
            if (QDir::cleanPath(QString::fromLocal8Bit(volume.device())) == QDir::cleanPath(devicePath)) {
                alreadyMounted = true;
                break;
            }
        }
        if (!alreadyMounted && !m_attemptedPartitions.contains(devicePath) &&
            !m_pendingPartitions.contains(devicePath))
            mountPartition(devicePath);
    }

    for (const QString &previous : m_connectedPartitions) {
        if (!connectedNow.contains(previous))
            m_attemptedPartitions.remove(previous);
    }
    m_connectedPartitions = connectedNow;

    const QList<QStorageInfo> volumes = QStorageInfo::mountedVolumes();
    bool activeVolumeMounted = false;
    for (const QStorageInfo &volume : volumes) {
        if (!volume.isValid() || !volume.isReady())
            continue;
        if (volume.rootPath() == m_activeMountPoint)
            activeVolumeMounted = true;
        if (!m_activeMountPoint.isEmpty())
            continue;
        if (!connectedNow.contains(QDir::cleanPath(QString::fromLocal8Bit(volume.device()))))
            continue;

        const QString filePath = autoplayFile(volume.rootPath());
        if (!filePath.isEmpty()) {
            m_activeMountPoint = volume.rootPath();
            qInfo("[UsbAutoPlay] playing marker target from %s", qPrintable(m_activeMountPoint));
            emit autoplayRequested(filePath);
        }
    }

    if (!m_activeMountPoint.isEmpty() && !activeVolumeMounted) {
        m_activeMountPoint.clear();
        emit driveRemoved();
    }
}