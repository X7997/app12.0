#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include "cloudmanager.h"
#include <QQmlContext>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>

/**
 * @brief 程序入口函数
 * @param argc 命令行参数个数
 * @param argv 命令行参数数组
 * @return 程序退出码
 * 
 * 程序启动流程：
 * 1. 创建Qt应用程序对象
 * 2. 创建云端管理器并连接服务器
 * 3. 将C++对象暴露给QML
 * 4. 加载QML界面
 * 5. 进入事件循环
 */
int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);

    CloudManager cloud;
    cloud.connectToCloud();

    QQmlApplicationEngine engine;

    engine.rootContext()->setContextProperty("cloudManager", &cloud);

    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);
    engine.loadFromModule("Iot", "Main");

    return QCoreApplication::exec();
}
