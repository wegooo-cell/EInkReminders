idf_component_register(
    SRCS "zectrix_canvas.cc" "zectrix_demo_ui.cc"
    INCLUDE_DIRS "." "include" "font"
    REQUIRES zectrix_board zectrix_epd zectrix_self_test esp_timer
)

target_compile_features(${COMPONENT_LIB} PUBLIC cxx_std_17)
