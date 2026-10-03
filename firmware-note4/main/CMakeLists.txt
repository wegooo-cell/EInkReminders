idf_component_register(SRCS "app_main.cc"
                       EMBED_FILES "settings_frames.bin" "standby_digits.bin" "standby_clock_masks.bin" "standby_default_photo.bin" "alert_sound.wav" "moof_dog_frames.bin" "easter_egg_frames.bin" "snooze_menu_frames.bin"
                       REQUIRES
                       zectrix_board
                       zectrix_demo_ui
                       zectrix_epd
                       captive_dns
                       esp_event
                       esp_http_server
                       esp_netif
                       esp_pm
                       esp_wifi
                       espressif__qrcode
                       json
                       mbedtls
                       nvs_flash
                       spiffs)
