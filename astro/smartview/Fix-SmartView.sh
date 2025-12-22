partitions=("system" "product" "odm" "system_ext" "system_dlkm" "vendor")
for partition in "${partitions[@]}"; do
    BPROP "$partition" "wlan.wfd.hdcp" "disabled"
    BPROP "$partition" "wifi.interface" "wlan0"
done
