if [[ "$EXTRA_MODEL" == SM-S938* ]]; then
# Now Brief
FF "FRAMEWORK_SUPPORT_PERSONALIZED_DATA_CORE" "TRUE"
FF "FRAMEWORK_SUPPORT_SMART_SUGGESTIONS_WIDGET" "TRUE"
FF "FRAMEWORK_SUPPORT_STACK_WIDGET_AUTO_ROTATION" "TRUE"

ADD_FROM_FW "extra" "system" "priv-app/SamsungSmartSuggestions" 
ADD_FROM_FW "extra" "system" "priv-app/Moments" 
ADD_FROM_FW "extra" "system" "etc/sysconfig/moments.xml"

# Environment adaptive display (Sead) + Display related
ADD_FROM_FW "extra" "system" "priv-app/EnvironmentAdaptiveDisplay" 
FF "SUPPORT_COLOR_LENS" "TRUE" 
# rest of patches are in services.jar 

# Enable AI support
FF "COMMON_SUPPORT_AI_AGENT" "TRUE"
FF "COMMON_CONFIG_AI_VERSION" "20253"
FF "COMMON_CONFIG_AWESOME_INTELLIGENCE" "202501"

# Audio Eraser
FF "AUDIO_CONFIG_MULTISOURCE_SEPARATOR" "{FastScanning_6, SourceSeparator_4, Version_1.3.0}"
ADD_FROM_FW "extra" "system" "etc/audio_ae_intervals.conf"
ADD_FROM_FW "extra" "system" "etc/audio_effects.xml"
ADD_FROM_FW "extra" "system" "etc/audio_effects_common.conf"
ADD_FROM_FW "extra" "system" "lib64/libmultisourceseparator.so"
ADD_FROM_FW "extra" "system" "lib64/libmultisourceseparator.audio.samsung.so"
ADD_FROM_FW "extra" "system" "etc/public.libraries-audio.samsung.txt"
ADD_FROM_FW "extra" "system" "etc/public.libraries-secinput.samsung.txt"

# AI Core / Language Model
ADD_FROM_FW "extra" "system" "priv-app/SamsungAiCore"
ADD_FROM_FW "extra" "system" "priv-app/OfflineLanguageModel_stub"
FF "GENAI_SUPPORT_OFFLINE_LANGUAGEMODEL" "TRUE"

# Sketchbook (edge panel)
ADD_FROM_FW "extra" "system" "app/SketchBook" 

# Wallpapers
ADD_FROM_FW "extra" "product" "priv-app/AICore" 
ADD_FROM_FW "extra" "product" "priv-app/AiWallpaper" 
ADD_FROM_FW "extra" "system" "priv-app/SpriteWallpaper"  #Used to animate Infinity wallpapers
ADD_FROM_FW "extra" "system" "priv-app/wallpaper-res"

# Photo Editor & Gallery
SILENT NUKE_BLOAT "PhotoEditor_Full"
ADD_FROM_FW "extra" "system" "priv-app/PhotoEditor_AIFull" 
ADD_FROM_FW "extra" "system" "priv-app/LiveEffectService" 
ADD_FROM_FW "extra" "system" "priv-app/VideoScan"
ADD_FROM_FW "extra" "system" "app/VisionModel-Stub" 
ADD_FROM_FW "extra" "system" "lib64/libArtifactDetector_v1.camera.samsung.so"
ADD_FROM_FW "extra" "system" "lib64/libphotohdr.so"
ADD_FROM_FW "extra" "system" "lib64/libtensorflowlite_gpu_delegate.so"
ADD_FROM_FW "extra" "system" "lib64/libmediacapture.so"
ADD_FROM_FW "extra" "system" "lib64/libmediacapture_jni.so"
ADD_FROM_FW "extra" "system" "lib64/libmediacaptureservice.so"
ADD_FROM_FW "extra" "system" "lib64/libvideoframedec.so"
ADD_FROM_FW "extra" "system" "lib64/libveframework.videoeditor.samsung.so"
ADD_FROM_FW "extra" "system" "lib64/libsbs.so"
ADD_FROM_FW "extra" "system" "lib64/libsimba.media.samsung.so"
FF "SAIV_SUPPORT_3DPHOTO" "TRUE"
FF "GALLERY_CONFIG_ZOOM_TYPE" "ZOOM_2K"
FF "GALLERY_SUPPORT_LOG_CORRECT_COLOR" "TRUE"
FF "MMFW_SUPPORT_AI_UPSCALER" "TRUE"

# Mediatek 
if [[ "$(GET_PROP system ro.product.system.device)" == "mssi" ]]; then
FF "LAUNCHER_CONFIG_ANIMATION_TYPE" "LowEnd"
else
# Live blur and launcher 
FF "LAUNCHER_CONFIG_ANIMATION_TYPE" "HighEnd"
FF "GRAPHICS_SUPPORT_3D_SURFACE_TRANSITION_FLAG" "TRUE"
FF "GRAPHICS_SUPPORT_CAPTURED_BLUR" "TRUE"
FF "GRAPHICS_SUPPORT_TOUCH_FAST_RESPONSE" "TRUE"
fi

#Permissions
ADD_FROM_FW "extra" "system" "etc/permissions" 
ADD_FROM_FW "extra" "system" "etc/default-permissions"

# Bixby 
ADD_FROM_FW "extra" "system" "priv-app/BixbyInterpreter" 

# Phone Packages
ADD_FROM_FW "extra" "system" "priv-app/SamsungInCallUI" 
ADD_FROM_FW "extra" "system" "priv-app/SamsungIntelliVoiceServices" 
ADD_FROM_FW "extra" "system" "priv-app/SamsungDialer" 

# Screenshot and Keyboard etc
ADD_FROM_FW "extra" "system" "app/HoneyBoard" 
ADD_FROM_FW "extra" "system" "app/SmartCapture" 
ADD_FROM_FW "extra" "system" "app/VisualCloudCore" 

# Ringtones ACH and bootanimation
ADD_FROM_FW "extra" "system" "media" 

# Extras
FF "GENAI_CONFIG_LLM_VERSION" "0.40"
FF "GENAI_SUPPORT_C2PA" "TRUE"
FF "GENAI_CONFIG_FOUNDATION_MODEL" "3B"

# REMOVE useless packages
FF "COMMON_CONFIG_SMARTTUTOR_PACKAGES_NAME" ""
FF "COMMON_CONFIG_SMARTTUTOR_PACKAGES_PATH" ""

#add useful features
FF "COMMON_SUPPORT_ULTRA_POWER_SAVING" "TRUE"

#Media Context
ADD_FROM_FW "extra" "system" "etc/mediacontextanalyzer"
FF "MMFW_SUPPORT_MEDIA_CONTEXT_ANALYZER" "TRUE"
ADD_FROM_FW "extra" "system" "lib64/libcontextanalyzer_jni.media.samsung.so"
ADD_FROM_FW "extra" "system" "lib64/video-highlight-arm64-v8a.so"
ADD_FROM_FW "extra" "system" "lib64/libmediacontextanalyzer.so"

local feature_xml="$WORKSPACE/system/system/etc/floating-feature.xml"

# TODO : a way for check device has NPU or not. Usually flagship device have NPU related props in the xml.
# We use this method until a new way found. For example : dm3q
if grep -q "NPU" "$feature_xml"; then
FF "MMFW_CONFIG_MEDIA_CONTEXT_ANALYZER_CORE" "NPU"
else
FF "MMFW_CONFIG_MEDIA_CONTEXT_ANALYZER_CORE" "GPU"
fi


# Semantic Search Core
FF "MSCH_SUPPORT_NLSEARCH" "TRUE"
ADD_FROM_FW "extra" "system" "etc/mediasearch"
ADD_FROM_FW "extra" "system" "priv-app/MediaSearch/MediaSearch.apk"
ADD_FROM_FW "extra" "system" "priv-app/SemanticSearchCore/SemanticSearchCore.apk"

# PhotoHDR (Will not work without 64bit only surfaceflinger)
# FF "MMFW_SUPPORT_PHOTOHDR" "TRUE"
# and other HDR* lines 

# Settings
ADD_FROM_FW "extra" "system" "priv-app/SecSettings" 
ADD_FROM_FW "extra" "system" "priv-app/SettingsProvider" 
ADD_FROM_FW "extra" "system" "priv-app/SecSettingsIntelligence.apk" 

fi