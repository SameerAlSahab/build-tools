#!/bin/bash

declare -a BLOAT_TARGETS=(
    # System Bloat
    "AuthFramework" "BCService" "CIDManager" "DeviceKeystring" "DiagMonAgent91" 
    "DigitalKey" "FacAtFunction" "FactoryTestProvider" "FotaAgent"  "KnoxGuard" "Rampart"
    "ModemServiceMode" "PaymentFramework" "SEMFactoryApp" "SOAgent7" "SamsungCarKeyFw" 
    "SamsungPass" "SamsungPassAutofill_v1" "SilentLog" "SmartEpdgTestApp" "Ts43AuthService" 
    "UnifiedTetheringProvision" "UnifiedVVM" "UsByod" "WebManual" "WlanTest" "wssyncmldm" "MyGalaxyService" 
    
    # Factory/Test
    "AutomationTest_FB" "DRParser" "FactoryCameraFB" 
	
    # Facebook
    "FBAppManager_NS" "FBInstaller_NS" "FBServices" 
    
    # TTS Voices
    "SamsungTTSVoice_de_DE_f00" "SamsungTTSVoice_en_GB_f00" "SamsungTTSVoice_en_US_l03" 
    "SamsungTTSVoice_es_ES_f00" "SamsungTTSVoice_es_MX_f00" "SamsungTTSVoice_es_US_f00" 
    "SamsungTTSVoice_es_US_l01" "SamsungTTSVoice_fr_FR_f00" "SamsungTTSVoice_hi_IN_f00" 
    "SamsungTTSVoice_it_IT_f00" "SamsungTTSVoice_pl_PL_f00" "SamsungTTSVoice_pt_BR_f00" 
    "SamsungTTSVoice_pt_BR_l01" "SamsungTTSVoice_ru_RU_f00" "SamsungTTSVoice_th_TH_f00" 
    "SamsungTTSVoice_vi_VN_f00" "SamsungTTSVoice_id_ID_f00" "SamsungTTSVoice_ar_AE_m00"
    
    # Samsung Apps
    "AssistantShell" "Notes40"  "SBrowser" 
    
    # Google Apps
    "Chrome" "DuoStub" "Gmail2" "Maps" "Messages" "YouTube" 
    
    # Third-Party
    "BlockchainBasicKit" "DictDiotekForSec" "HMT" "MoccaMobile" "OneDrive_Samsung_v3" 
    "PlayAutoInstallConfig" "Scone" "Upday" "VzCloud" 
    
    # Game
     "GameHome" 
    
    # Overlays
    "GmsConfigOverlaySearchSelector.apk" "SearchSelector"
)



NUKE_BLOAT "${BLOAT_TARGETS[@]}"


REMOVE "system" "hidden"
REMOVE "system" "preload"

EXISTS "stock" "system" "priv-app/GameDriver-SM8*50" || REMOVE "system" "priv-app/GameDriver-SM8*50"


    REMOVE   "system" "bin/fabric_crypto"
    REMOVE   "system" "etc/vintf/manifest/fabric_crypto_manifest.xml"
    REMOVE   "system" "etc/permissions/FabricCryptoLib.xml"
    REMOVE   "system" "etc/init/fabric_crypto.rc"
    REMOVE   "system" "etc/permissions/privapp-permissions-com.samsung.android.kmxservice.xml"
    REMOVE   "system" "lib64/vendor.samsung.hardware.security.fkeymaster-V1-cpp.so"
    REMOVE   "system" "lib64/vendor.samsung.hardware.security.fkeymaster-V1-ndk.so"
    REMOVE   "system" "lib64/com.samsung.security.fabric.cryptod-V1-cpp.so"
    REMOVE   "system" "framework/FabricCryptoLib.jar"

