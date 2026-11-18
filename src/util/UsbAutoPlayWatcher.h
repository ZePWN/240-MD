#pragma once

#include <QObject>
#include <QElapsedTimer>
#include <QHash>
#include <QSet>
#include <QTimer>
#include <QVariantMap>

class UsbAutoPlayWatcher : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool hiMdLoading READ hiMdLoading NOTIFY hiMdLoadingChanged)
    Q_PROPERTY(QVariantMap hiMdDisc READ hiMdDisc NOTIFY hiMdDiscChanged)

public:
    explicit UsbAutoPlayWatcher(QObject *parent = nullptr);
    void start();
    bool hiMdLoading() const { return !m_loadingHiMdDevice.isEmpty(); }
    QVariantMap hiMdDisc() const { return m_hiMdDisc; }
    Q_INVOKABLE bool activateHiMd(const QString &filePath);
    Q_INVOKABLE void releasePlayback(const QString &filePath);

signals:
    void autoplayRequested(const QString &filePath);
    void hiMdAutoplayRequested(const QVariantMap &disc);
    void driveRemoved();
    void hiMdLoadingChanged();
    void hiMdLoadError(const QString &message);
    void hiMdDiscChanged();

private slots:
    void scan();

private:
    friend class UsbAutoPlayWatcherTest;

    void mountPartition(const QString &devicePath);
    QVariantMap autoplayFile(const QString &mountPoint, bool identifyMedia) const;
    bool shouldAttemptMount(const QString &devicePath) const;
    static bool isHiMdDevice(const QString &sysPath);
    void updateHiMdLoading(const QSet<QString> &presentDevices);
    void finishHiMdLoading(const QString &devicePath, const QString &error = {});
    void processMountedVolumes(const QList<QPair<QString, QString>> &volumes,
                               const QSet<QString> &connectedDevices);

    QTimer m_pollTimer;
    QElapsedTimer m_elapsed;
    QSet<QString> m_connectedPartitions;
    QHash<QString, qint64> m_attemptedPartitions;
    QSet<QString> m_pendingPartitions;
    QString m_activeMountPoint;
    QString m_activeDevice;
    QString m_activeFilePath;
    bool m_activeHiMd = false;
    QSet<QString> m_seenVolumes;
    QSet<QString> m_hiMdDevices;
    QSet<QString> m_hiMdPresent;
    QString m_hiMdDevice;
    QString m_hiMdMountPoint;
    QVariantMap m_hiMdDisc;
    QString m_loadingHiMdDevice;
    qint64 m_hiMdLoadingStarted = 0;
    QSet<QString> m_finishedHiMdDevices;
};