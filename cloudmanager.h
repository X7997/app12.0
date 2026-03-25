#ifndef CLOUDMANAGER_H
#define CLOUDMANAGER_H

#include <QObject>
#include <QtMqtt/QMqttClient>
#include <QNetworkAccessManager>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QJsonParseError>
#include <QTimer>

/**
 * @brief 云端通信管理器类
 * 
 * 该类负责处理MQTT连接、消息收发、位置解析等核心功能。
 * 是APP与阿里云EMQX服务器通信的桥梁。
 */
class CloudManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int connectionStatus READ connectionStatus NOTIFY connectionStatusChanged)

public:
    explicit CloudManager(QObject *parent = nullptr);

    /**
     * @brief 连接到阿里云MQTT服务器
     * 
     * 配置服务器地址、端口、用户名密码，并发起连接。
     * 连接成功后会自动订阅"4G"主题。
     */
    void connectToCloud();

    /**
     * @brief 发送指令到云端
     * @param action 指令类型（如"call"、"sms"）
     * @param param 指令参数（JSON格式字符串）
     * 
     * 通过MQTT发布消息到"4G"主题，用于控制终端设备。
     */
    Q_INVOKABLE void sendCommand(QString action, QString param);

    /**
     * @brief 刷新当前位置
     * 
     * 使用最后一次接收到的经纬度重新请求高德API获取地址。
     */
    Q_INVOKABLE void refreshLocation();

    /**
     * @brief 获取当前连接状态
     * @return 0=未连接, 1=连接中, 2=已连接
     */
    Q_INVOKABLE int connectionStatus() const { return m_connectionStatus; }

signals:
    /**
     * @brief 位置更新信号
     * @param lonLat 经纬度字符串
     * @param address 详细地址
     * 
     * 当收到设备位置数据并解析成功后发出。
     */
    void locationUpdated(QString lonLat, QString address);

    /**
     * @brief 连接状态变化信号
     * @param status 新的连接状态
     */
    void connectionStatusChanged(int status);

    /**
     * @brief 指令执行结果信号
     * @param result 结果描述
     */
    void commandResult(QString result);

    void serialDataReceived(QString data); // 对应 QML 里的 onSerialDataReceived

private slots:
    /**
     * @brief MQTT连接成功回调
     * 
     * 连接成功后订阅"4G"主题，更新连接状态。
     */
    void onMQTTConnected();

    /**
     * @brief MQTT断开连接回调
     * 
     * 断开后启动重连定时器。
     */
    void onMQTTDisconnected();

private:
    /**
     * @brief 根据经纬度获取详细地址
     * @param lon 经度
     * @param lat 纬度
     * 
     * 调用高德地图逆地理编码API，将经纬度转换为可读地址。
     */
    void fetchAddress(double lon, double lat);

    /**
     * @brief 重连到云端
     * 
     * 由定时器触发，尝试重新连接MQTT服务器。
     */
    void reconnectToCloud();

private:
    QMqttClient *m_client;              // MQTT客户端对象
    QNetworkAccessManager *m_netManager; // 网络请求管理器（用于高德API）
    int m_connectionStatus = 0;         // 连接状态：0未连接/1连接中/2已连接
    QTimer *m_reconnectTimer;           // 重连定时器
    QTimer *m_refreshTimer;             // 刷新定时器
    double m_lastLon = 0;               // 最后接收的经度
    double m_lastLat = 0;               // 最后接收的纬度
    bool m_hasLocation = false;         // 是否有有效位置数据
};

#endif // CLOUDMANAGER_H
