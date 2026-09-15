idf_component_register(SRCS "app_main.cc"
                       EMBED_FILES "settings_frames.bin" "alert_sound.wav"
                       REQUIRES
                       zectrix_board
                       zectrix_demo_ui
                       zectrix_epd
                       captive_dns
                       esp_event
                       esp_http_server
                       esp_netif
                       esp_wifi
                       espressif__qrcode
                       json
                       mbedtls
                       nvs_flash
                       spiffs)
