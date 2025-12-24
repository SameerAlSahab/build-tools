#
#
# by Ian Macdonald, enhanced by afaneh92
#
#  Disables:
#  - File-Based Encryption (FBE)
#  - Full-Disk Encryption (FDE)
#  - Factory Reset Protection (FRP)
#  - Stock Recovery
#

LOG_BEGIN "Removing Samsung Encryption"

    find "$WORKSPACE/vendor/etc" -type f -name "fstab*" | while read -r fstab; do
        
        sed -i \
            's/^\([^#].*\)fileencryption=[^,]*\(.*\)$/# &\n\1encryptable\2/' \
            "$fstab"

        
        sed -i \
            's/^\([^#].*\)forceencrypt=[^,]*\(.*\)$/# &\n\1encryptable\2/' \
            "$fstab"
    done



BPROP "system" "ro.frp.pst" ""
BPROP "product" "ro.frp.pst" ""


    rm -f \
        "$WORKSPACE/vendor/recovery-from-boot.p" \
        "$WORKSPACE/vendor/bin/install-recovery.sh" \
        "$WORKSPACE/vendor/etc/recovery-resource.dat" 2>/dev/null


