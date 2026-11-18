#include "UsbAutoPlayWatcher.h"

#include <QDir>
#include <QCryptographicHash>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QStorageInfo>

namespace {
constexpr qint64 kHiMdLoadTimeoutMs = 60000;

QByteArray readSysfsValue(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    return file.readAll().trimmed();
}
}

UsbAutoPlayWatcher::UsbAutoPlayWatcher(QObject *parent)
    : QObject(parent)
{
    m_elapsed.start();
    m_pollTimer.setInterval(1000);
    connect(&m_pollTimer, &QTimer::timeout, this, &UsbAutoPlayWatcher::scan);
}

void UsbAutoPlayWatcher::start()
{
    scan();
    m_pollTimer.start();
}

QVariantMap UsbAutoPlayWatcher::autoplayFile(const QString &mountPoint, bool identifyMedia) const
{
    QFile marker(QDir(mountPoint).filePath(QStringLiteral("Autoplay.txt")));
    if (!marker.open(QIODevice::ReadOnly | QIODevice::Text))
        return {};

    const QStringList lines = QString::fromUtf8(marker.readAll()).split('\n');
    const QString fileName = lines.value(0).trimmed();
    QString title;
    for (qsizetype i = 1; i < lines.size(); ++i) {
        const QString line = lines.at(i).trimmed();
        if (line.isEmpty())
            continue;
        if (!line.startsWith(QStringLiteral("Title:"), Qt::CaseInsensitive) || !title.isEmpty()) {
            qWarning("[UsbAutoPlay] invalid marker metadata in %s", qPrintable(marker.fileName()));
            return {};
        }
        title = line.mid(6).trimmed();
        if (title.isEmpty()) {
            qWarning("[UsbAutoPlay] empty title in %s", qPrintable(marker.fileName()));
            return {};
        }
    }
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

    QVariantMap result = {{QStringLiteral("filePath"), canonicalFile},
                          {QStringLiteral("title"), title.isEmpty() ? fileName : title}};
    if (identifyMedia) {
        QFile media(canonicalFile);
        if (!media.open(QIODevice::ReadOnly)) {
            qWarning("[UsbAutoPlay] cannot read %s: %s", qPrintable(canonicalFile),
                     qPrintable(media.errorString()));
            return {};
        }
        const QByteArray sample = media.read(65536);
        if (media.error() != QFileDevice::NoError) {
            qWarning("[UsbAutoPlay] cannot read %s: %s", qPrintable(canonicalFile),
                     qPrintable(media.errorString()));
            return {};
        }
        QCryptographicHash hash(QCryptographicHash::Sha256);
        hash.addData(QByteArray::number(media.size()));
        hash.addData(QByteArray(":"));
        hash.addData(sample);
        result.insert(QStringLiteral("historyKey"),
                      QStringLiteral("hi-md:") + QString::fromLatin1(hash.result().toHex()));
    }
    return result;
}

bool UsbAutoPlayWatcher::activateHiMd(const QString &filePath)
{
    if (filePath.isEmpty() || m_hiMdDisc.value(QStringLiteral("filePath")).toString() != filePath)
        return false;
    m_activeMountPoint = m_hiMdMountPoint;
    m_activeDevice = m_hiMdDevice;
    m_activeFilePath = filePath;
    m_activeHiMd = true;
    return true;
}

void UsbAutoPlayWatcher::releasePlayback(const QString &filePath)
{
    if (filePath != m_activeFilePath)
        return;
    m_activeMountPoint.clear();
    m_activeDevice.clear();
    m_activeFilePath.clear();
    m_activeHiMd = false;
}

void UsbAutoPlayWatcher::mountPartition(const QString &devicePath)
{
    m_attemptedPartitions.insert(devicePath, m_elapsed.elapsed());
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

bool UsbAutoPlayWatcher::shouldAttemptMount(const QString &devicePath) const
{
    const auto attempt = m_attemptedPartitions.constFind(devicePath);
    return !m_pendingPartitions.contains(devicePath) &&
           (attempt == m_attemptedPartitions.cend() || m_elapsed.elapsed() - *attempt >= 10000);
}

bool UsbAutoPlayWatcher::isHiMdDevice(const QString &sysPath)
{
    QDir dir(sysPath);
    while (dir.path() != QLatin1String("/") && dir.path() != QLatin1String("/sys")) {
        if (readSysfsValue(dir.filePath("idVendor")).toLower() == "054c" &&
            readSysfsValue(dir.filePath("product")).toLower().contains("hi-md"))
            return true;
        if (!dir.cdUp())
            break;
    }
    return false;
}

void UsbAutoPlayWatcher::updateHiMdLoading(const QSet<QString> &presentDevices)
{
    m_hiMdPresent = presentDevices;
    m_finishedHiMdDevices.intersect(presentDevices);
    if (!m_loadingHiMdDevice.isEmpty() && !presentDevices.contains(m_loadingHiMdDevice)) {
        const QString device = m_loadingHiMdDevice;
        finishHiMdLoading(device);
        m_finishedHiMdDevices.remove(device);
    }

    if (!m_loadingHiMdDevice.isEmpty() &&
        m_elapsed.elapsed() - m_hiMdLoadingStarted >= kHiMdLoadTimeoutMs) {
        const QString device = m_loadingHiMdDevice;
        qWarning("[UsbAutoPlay] timed out waiting for Hi-MD %s to mount", qPrintable(device));
        finishHiMdLoading(device, QStringLiteral("HI-MD COULD NOT BE LOADED"));
    }

    if (!m_loadingHiMdDevice.isEmpty())
        return;
    for (const QString &device : presentDevices) {
        if (!m_finishedHiMdDevices.contains(device)) {
            m_loadingHiMdDevice = device;
            m_hiMdLoadingStarted = m_elapsed.elapsed();
            emit hiMdLoadingChanged();
            break;
        }
    }
}

void UsbAutoPlayWatcher::finishHiMdLoading(const QString &devicePath, const QString &error)
{
    if (devicePath != m_loadingHiMdDevice)
        return;
    m_finishedHiMdDevices.insert(devicePath);
    m_loadingHiMdDevice.clear();
    emit hiMdLoadingChanged();
    if (!error.isEmpty())
        emit hiMdLoadError(error);
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
    QSet<QString> hiMdPresent;
    QSet<QString> hiMdDevices;
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

        if (isHiMdDevice(sysPath)) {
            hiMdDevices.insert(devicePath);
            if (readSysfsValue(entry.filePath() + QStringLiteral("/size")).toULongLong() > 0)
                hiMdPresent.insert(devicePath);
        }

        bool alreadyMounted = false;
        for (const QStorageInfo &volume : QStorageInfo::mountedVolumes()) {
            if (QDir::cleanPath(QString::fromLocal8Bit(volume.device())) == QDir::cleanPath(devicePath)) {
                alreadyMounted = true;
                break;
            }
        }
        if (!alreadyMounted && shouldAttemptMount(devicePath))
            mountPartition(devicePath);
    }

    for (const QString &previous : m_connectedPartitions) {
        if (!connectedNow.contains(previous))
            m_attemptedPartitions.remove(previous);
    }
    m_connectedPartitions = connectedNow;
    m_hiMdDevices = hiMdDevices;
    updateHiMdLoading(hiMdPresent);

    QList<QPair<QString, QString>> volumes;
    for (const QStorageInfo &volume : QStorageInfo::mountedVolumes()) {
        if (volume.isValid() && volume.isReady())
            volumes.append({volume.rootPath(), QDir::cleanPath(QString::fromLocal8Bit(volume.device()))});
    }
    processMountedVolumes(volumes, connectedNow);
}

void UsbAutoPlayWatcher::processMountedVolumes(const QList<QPair<QString, QString>> &volumes,
                                                const QSet<QString> &connectedDevices)
{
    QSet<QString> mountedDevices;
    for (const auto &volume : volumes) {
        if (!connectedDevices.contains(volume.second))
            continue;
        const bool hiMd = m_hiMdPresent.contains(volume.second);
        // A Hi-MD block device can remain connected after its disc is ejected.
        if (m_hiMdDevices.contains(volume.second) && !hiMd)
            continue;
        mountedDevices.insert(volume.second);
        if (m_seenVolumes.contains(volume.second))
            continue;
        const QVariantMap disc = autoplayFile(volume.first, hiMd);
        if (!disc.isEmpty()) {
            finishHiMdLoading(volume.second);
            if (hiMd) {
                m_seenVolumes.insert(volume.second);
                m_hiMdDevice = volume.second;
                m_hiMdMountPoint = volume.first;
                m_hiMdDisc = disc;
                emit hiMdDiscChanged();
                emit hiMdAutoplayRequested(disc);
            } else if (m_activeMountPoint.isEmpty()) {
                m_seenVolumes.insert(volume.second);
                m_activeMountPoint = volume.first;
                m_activeDevice = volume.second;
                m_activeFilePath = disc.value(QStringLiteral("filePath")).toString();
                m_activeHiMd = false;
                emit autoplayRequested(m_activeFilePath);
            }
        } else if (volume.second == m_loadingHiMdDevice) {
            qWarning("[UsbAutoPlay] no valid Autoplay.txt target on Hi-MD %s",
                     qPrintable(volume.second));
            finishHiMdLoading(volume.second, QStringLiteral("NO HI-MD AUTOPLAY FILE"));
        }
    }

    m_seenVolumes.intersect(mountedDevices);
    if (!m_hiMdDevice.isEmpty() &&
        (!mountedDevices.contains(m_hiMdDevice) || !m_hiMdPresent.contains(m_hiMdDevice))) {
        m_hiMdDevice.clear();
        m_hiMdMountPoint.clear();
        m_hiMdDisc.clear();
        emit hiMdDiscChanged();
    }
    if (!m_activeDevice.isEmpty() &&
        (!mountedDevices.contains(m_activeDevice) ||
         (m_activeHiMd && !m_hiMdPresent.contains(m_activeDevice)))) {
        releasePlayback(m_activeFilePath);
        emit driveRemoved();
    }
}