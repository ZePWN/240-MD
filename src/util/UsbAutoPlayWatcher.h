#pragma once

#include <QObject>
#include <QSet>
#include <QTimer>

class QProcess;

class UsbAutoPlayWatcher : public QObject {
    Q_OBJECT

public:
    explicit UsbAutoPlayWatcher(QObject *parent = nullptr);
    void start();

signals:
    void autoplayRequested(const QString &filePath);
    void driveRemoved();

private slots:
    void scan();

private:
    void mountPartition(const QString &devicePath);
    QString autoplayFile(const QString &mountPoint) const;

    QTimer m_pollTimer;
    QSet<QString> m_connectedPartitions;
    QSet<QString> m_attemptedPartitions;
    QSet<QString> m_pendingPartitions;
    QString m_activeMountPoint;
};