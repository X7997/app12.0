#include "cloudmanager.h"
#include <QDebug>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QUrl>
#include <QSslConfiguration>

/**
 * @brief 构造函数 - 初始化所有成员对象并建立信号槽连接
 * 
 * 主要工作：
 * 1. 创建MQTT客户端和网络管理器
 * 2. 创建定时器（重连、刷新）
 * 3. 连接MQTT的各种信号到对应的槽函数
 * 4. 设置消息接收处理器（核心数据解析逻辑）
 */
CloudManager::CloudManager(QObject *parent) : QObject(parent)
{
    // ==========================================
    // 【安全插入区】在这里加上你的初始默认位置
    // ==========================================
    m_lastLon = 113.568817;
    m_lastLat = 23.303581;
    m_hasLocation = true;  // 骗过系统，让它以为我们已经有位置了
    // ==========================================
    
    m_client = new QMqttClient(this);
    m_netManager = new QNetworkAccessManager(this);

    m_reconnectTimer = new QTimer(this);
    m_refreshTimer = new QTimer(this);
    m_reconnectTimer->setInterval(5000);
    m_refreshTimer->setInterval(3000);

    connect(m_client, &QMqttClient::errorChanged, this, [this](QMqttClient::ClientError error) {
        qDebug() << "MQTT发生错误，错误码:" << error;
    });

    connect(m_client, &QMqttClient::connected, this, &CloudManager::onMQTTConnected);
    connect(m_client, &QMqttClient::disconnected, this, &CloudManager::onMQTTDisconnected);
    connect(m_reconnectTimer, &QTimer::timeout, this, &CloudManager::reconnectToCloud);

    connect(m_client, &QMqttClient::messageReceived, this, [this](const QByteArray &message, const QMqttTopicName &topic) {
        QString strMsg = QString::fromUtf8(message);
        qDebug() << "收到原始消息:" << strMsg;

        emit serialDataReceived(strMsg);

        QJsonParseError jsonError;
        QJsonDocument doc = QJsonDocument::fromJson(message, &jsonError);

        if (jsonError.error != QJsonParseError::NoError) {
            qDebug() << "JSON解析错误:" << jsonError.errorString();
            return;
        }

        if (!doc.isObject()) {
            qDebug() << "JSON不是对象格式";
            return;
        }

        QJsonObject rootObj = doc.object();
        qDebug() << "JSON根对象 keys:" << rootObj.keys();

        double lon = 0;
        double lat = 0;
        bool found = false;

        if (rootObj.contains("content")) {
            QJsonObject contentObj = rootObj.value("content").toObject();
            if (contentObj.contains("services")) {
                QJsonArray servicesArray = contentObj.value("services").toArray();

                if (!servicesArray.isEmpty()) {
                    QJsonObject serviceObj = servicesArray.first().toObject();
                    QJsonObject propertiesObj = serviceObj.value("properties").toObject();

                    if (propertiesObj.contains("lon") && propertiesObj.contains("lat")) {
                        lon = propertiesObj.value("lon").toDouble();
                        lat = propertiesObj.value("lat").toDouble();
                        found = true;
                    }
                }
            }
        }

        if (!found && rootObj.contains("services")) {
            QJsonArray servicesArray = rootObj.value("services").toArray();
            for (int i = 0; i < servicesArray.size(); i++) {
                QJsonObject serviceObj = servicesArray.at(i).toObject();
                QJsonObject propertiesObj = serviceObj.value("properties").toObject();

                if (propertiesObj.contains("lon") && propertiesObj.contains("lat")) {
                    lon = propertiesObj.value("lon").toDouble();
                    lat = propertiesObj.value("lat").toDouble();
                    found = true;
                    break;
                }
            }
        }

        if (!found && rootObj.contains("lon") && rootObj.contains("lat")) {
            lon = rootObj.value("lon").toDouble();
            lat = rootObj.value("lat").toDouble();
            found = true;
        }

        if (found && lon != 0 && lat != 0) {
            qDebug() << "成功提取经纬度: 经度" << lon << "纬度" << lat;
            m_lastLon = lon;
            m_lastLat = lat;
            m_hasLocation = true;
            fetchAddress(lon, lat);
        } else {
            qDebug() << "未能从消息中提取到经纬度";
        }
    });
    fetchAddress(m_lastLon, m_lastLat);
}

/**
 * @brief MQTT连接成功回调
 * 
 * 连接成功后执行：
 * 1. 更新连接状态为"已连接"
 * 2. 停止重连定时器
 * 3. 订阅"4G"主题（接收设备上报的数据）
 */
void CloudManager::onMQTTConnected()
{
    qDebug() << "====== 成功连接到阿里云 EMQX！ ======";
    m_connectionStatus = 2;
    emit connectionStatusChanged(m_connectionStatus);

    if (m_reconnectTimer->isActive()) {
        m_reconnectTimer->stop();
    }

    QString topicStr = "4G";
    m_client->subscribe(topicStr, 0);
    qDebug() << "已订阅主题:" << topicStr;
}

/**
 * @brief MQTT断开连接回调
 * 
 * 断开后执行：
 * 1. 更新连接状态为"未连接"
 * 2. 启动重连定时器（5秒后尝试重连）
 */
void CloudManager::onMQTTDisconnected()
{
    qDebug() << "====== 已断开与云端的连接 ======";
    m_connectionStatus = 0;
    emit connectionStatusChanged(m_connectionStatus);

    if (!m_reconnectTimer->isActive()) {
        m_reconnectTimer->start();
        qDebug() << "将在5秒后尝试重连...";
    }
}

/**
 * @brief 重连到云端
 * 
 * 由重连定时器触发，检查连接状态并尝试重新连接。
 * 使用MQTT 3.1.1协议版本。
 */
void CloudManager::reconnectToCloud()
{
    if (m_client->state() != QMqttClient::Disconnected) {
        m_reconnectTimer->stop();
        return;
    }

    qDebug() << "正在尝试重连...";
    m_connectionStatus = 1;
    emit connectionStatusChanged(m_connectionStatus);

    m_client->setProtocolVersion(QMqttClient::MQTT_3_1_1);
    m_client->connectToHost();
}

/**
 * @brief 连接到阿里云MQTT服务器
 * 
 * 配置并连接到阿里云EMQX服务器：
 * - 服务器地址：101.201.62.164
 * - 端口：1883
 * - 客户端ID：AgriEdge_APP_Client_01
 * - 用户名：Iot_APP
 * - 密码：123456
 * 
 * 【修改服务器配置请改这里】
 */
void CloudManager::connectToCloud()
{
    m_connectionStatus = 1;
    emit connectionStatusChanged(m_connectionStatus);

    m_client->setHostname("8.129.129.246");
    m_client->setPort(1883);
    m_client->setClientId("APP_Client_01");
    m_client->setUsername("Iot_APP");
    m_client->setPassword("123456");

    m_client->connectToHost();
}

/**
 * @brief 刷新当前位置
 * 
 * 使用缓存的经纬度重新请求地址解析。
 * 如果没有位置数据则提示用户。
 */
void CloudManager::refreshLocation()
{
    if (!m_hasLocation) {
        qDebug() << "没有可刷新的位置数据";
        emit locationUpdated("等待数据接入", "暂无位置数据，请先接收设备数据");
        return;
    }

    qDebug() << "刷新位置: 经度" << m_lastLon << "纬度" << m_lastLat;
    fetchAddress(m_lastLon, m_lastLat);
}

/**
 * @brief 根据经纬度获取详细地址
 * @param lon 经度
 * @param lat 纬度
 * 
 * 调用高德地图逆地理编码API：
 * - API地址：http://restapi.amap.com/v3/geocode/regeo
 * - 需要高德API Key
 * 
 * 【修改高德API Key请改这里】
 */
void CloudManager::fetchAddress(double lon, double lat)
{
    QString amapKey = "be806420bcbe36f0e573770e212482d4";
    QString urlStr = QString("http://restapi.amap.com/v3/geocode/regeo?location=%1,%2&key=%3&radius=100")
                         .arg(lon).arg(lat).arg(amapKey);

    qDebug() << "请求地址API:" << urlStr;

    QNetworkRequest request((QUrl(urlStr)));

    QSslConfiguration config = QSslConfiguration::defaultConfiguration();
    config.setPeerVerifyMode(QSslSocket::VerifyNone);
    request.setSslConfiguration(config);

    QNetworkReply *reply = m_netManager->get(request);

    connect(reply, &QNetworkReply::finished, this, [=]() {
        QString lonLatStr = QString("E: %1°   N: %2°").arg(lon).arg(lat);

        if (reply->error() == QNetworkReply::NoError) {
            QByteArray response = reply->readAll();
            qDebug() << "高德API返回:" << response;

            QJsonDocument doc = QJsonDocument::fromJson(response);
            if (!doc.isObject()) {
                qDebug() << "高德API返回不是JSON对象";
                emit locationUpdated(lonLatStr, "地址解析失败");
                reply->deleteLater();
                return;
            }

            QJsonObject rootObj = doc.object();
            QString status = rootObj.value("status").toString();
            QString infoCode = rootObj.value("infocode").toString();

            qDebug() << "高德API状态:" << status << "infoCode:" << infoCode;

            if (status == "1" && infoCode == "10000") {
                QJsonObject regeocodeObj = rootObj.value("regeocode").toObject();
                QString baseAddress = regeocodeObj.value("formatted_address").toString();

                qDebug() << "解析出地址:" << baseAddress;
                emit locationUpdated(lonLatStr, baseAddress);
            } else {
                QString info = rootObj.value("info").toString();
                qDebug() << "地址解析失败:" << info;
                emit locationUpdated(lonLatStr, QString("地址解析失败: %1").arg(info));
            }
        } else {
            qDebug() << "网络请求失败:" << reply->errorString() << "错误码:" << reply->error();
            emit locationUpdated(lonLatStr, "报错: " + reply->errorString());
        }
        reply->deleteLater();
    });
}

/**
 * @brief 发送指令到云端
 * @param action 指令类型（如"call"、"sms"）
 * @param param 指令参数（JSON格式字符串）
 * 
 * 构建JSON消息并发布到"4G"主题：
 * {
 *   "command_name": "call/sms",
 *   "parameter": "{...}"
 * }
 * 
 * 【修改发布主题请改这里的topic变量】
 */
void CloudManager::sendCommand(QString action, QString param)
{
    if (m_client->state() != QMqttClient::Connected) {
        qDebug() << "未连接到云端，指令发送失败！";
        emit commandResult("未连接到云端，指令发送失败！");
        return;
    }

    QString topic = "4G";

    QJsonObject payloadObj;
    payloadObj["command_name"] = action;
    payloadObj["parameter"] = param;
    QJsonDocument doc(payloadObj);
    QByteArray msg = doc.toJson(QJsonDocument::Compact);

    m_client->publish(QMqttTopicName(topic), msg, 0);

    qDebug() << "已向阿里云主题[" << topic << "]发送指令:" << msg;
    emit commandResult(QString("指令已发送: %1 %2").arg(action).arg(param));
}
