# Device props
MODEL_NAME="Galaxy S20 5G"
CODENAME="x1q"
SIOP_POLICY_NAME=siop_x1q_sm8250
VNDK="30"
STOCK_MODEL="SM-G981N"
STOCK_CSC="KOO"
STOCK_IMEI="355995110205095"

# The firmware to be used as source 
# r9q is less bloated and similar structure as x1q
MODEL="SM-G990B"
CSC="EUX" 
IMEI="353718681234563"

# Extra firmware which is optional
#EXTRA_MODEL=""
#EXTRA_CSC=""
#EXTRA_IMEI=""


# External
FILESYSTEM=ext4
# TODO: Add erofs on ramdisk beside kernel
#FILESYSTEM="erofs"


# Specs
DEVICE_HAVE_SPEN_SUPPORT=false
DEVICE_HAVE_QHD_PANEL=true
DEVICE_HAVE_HIGH_REFRESH_RATE=true
DEVICE_DISPLAY_HFR_MODE=3 # S20 5G supports adaptive refresh rate 
DEVICE_DISPLAY_REFRESH_RATE_VALUES_HZ="30,48,60,96,120" #30 , 48 , 60 , 96 and 120 Hz are supported by S20 5G

