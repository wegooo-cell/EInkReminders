cmake_minimum_required(VERSION 3.16)

# Build only the reminder firmware's dependency closure. This also keeps the
# browser image small and avoids pulling unrelated Bluetooth/MQTT demo stacks.
set(COMPONENTS main)
set(PROJECT_VER "1.0.0")
include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(eink_reminders_note4)
