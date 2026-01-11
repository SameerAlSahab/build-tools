# Basic
FF "SETTINGS_CONFIG_BRAND_NAME" "$MODEL_NAME"
FF "CONFIG_SIOP_POLICY_FILENAME" "$SIOP_POLICY_NAME"
FF "system" "ro.factory.model" "$STOCK_MODEL"

if $DEVICE_HAVE_SPEN_SUPPORT== true && EXISTS "system" "priv-app/AirCommand" ; then
LOG_INFO "Device or source both have spen support. Ignoring..."
elif 
$DEVICE_HAVE_SPEN_SUPPORT==false && EXITS "system" "priv-app/AirCommand" ; then
SILENT NUKE_BLOAT "AirCommand" "AirGlance" 
FF "SUPPORT_EAGLE_EYE" ""
elif
device have but source dont then 
ADD_FROM_FW "pa3q" "system" "priv-app/AirCommand"
FF "SUPPORT_EAGLE_EYE" "TRUE"
same add_from_fw for other packages
else
both dont have ignore

now , DEVICE_HAVE_QHD_PANEL == true then;
FF "COMMON_CONFIG_DYN_RESOLUTION_CONTROL" "WQHD,FHD,HD"
else
FF "SEC_FLOATING_FEATURE_COMMON_CONFIG_DYN_RESOLUTION_CONTROL" ""

DEVICE_HAVE_HIGH_REFRESH_RATE ==true && GET_PROP "vendor" "ro.surface_flinger.enable_frame_rate_override" is not value true or no line or return  ; then

LOG_INFO "Adding Adaptive Refresh rate"
BPROP "vendor" "debug.sf.show_refresh_rate_overlay_render_rate" "true"
BPROP "vendor" "ro.surface_flinger.game_default_frame_rate_override" "60"
BPROP "vendor" "ro.surface_flinger.use_content_detection_for_refresh_rate" "true"
BPROP "vendor" "ro.surface_flinger.set_idle_timer_ms" "250"
BPROP "vendor" "ro.surface_flinger.set_touch_timer_ms" "300"
BPROP "vendor" "ro.surface_flinger.set_display_power_timer_ms" "200"
BPROP "vendor" "ro.surface_flinger.enable_frame_rate_override" "true"

now if var DEVICE_DISPLAY_HFR_VALUE and another one exist or given then do
FF "LCD_CONFIG_HFR_MODE" "$DEVICE_DISPLAY_HFR_MODE"
FF "LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE" "$DEVICE_DISPLAY_REFRESH_RATE_VALUES_HZ"





