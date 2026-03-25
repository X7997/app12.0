cmake_minimum_required(VERSION 3.16)

project(Iot VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(QT_QML_GENERATE_QMLLS_INI ON)

add_subdirectory(qtmqtt)

find_package(Qt6 REQUIRED COMPONENTS Quick Network Svg)

qt_standard_project_setup(REQUIRES 6.5)

# 1. 这里只放纯 C++ 代码，把那个捣乱的 res.qrc 删掉！
qt_add_executable(appIot
    main.cpp
    cloudmanager.cpp
    cloudmanager.h
)

# 2. QML 和 图片资源全部交给这里自动管理 (只保留一个 RESOURCES)
qt_add_qml_module(appIot
    URI Iot
    VERSION 1.0
    QML_FILES
        Main.qml
    RESOURCES
        images/sms.png
        images/refresh.png
        images/phone.png
        images/emergency.png
)

# 3. 链接需要的库
target_link_libraries(appIot
    PRIVATE
    Qt6::Quick
    Qt6::Network
    Qt6::Mqtt
    Qt6::Svg
)