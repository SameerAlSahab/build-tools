#
# https://github.com/ShaDisNX255/NcX_Stock/commit/20e007bd742f25d4a2cac204deec575f16d3a012#diff-0ca3446492dfceaede78856b8c99c3bc3eed8837e7884464bfa2d1e3f4a9ac73
# <SEC_FLOATING_FEATURE_SYSTEM_CONFIG_SIOP_POLICY_FILENAME>siop_codename_soc</SEC_FLOATING_FEATURE_SYSTEM_CONFIG_SIOP_POLICY_FILENAME> already fixes this issue
# But actual reason using this still is this warning also appears when there are a few edits to the GPU freq table in the kernel.
#


find . -type f -name "*.smali" | while read -r file; do
    if grep -q '"SSRM Warning"' "$file" && grep -q '"I got it"' "$file"; then
        method_line=$(grep -B 20 '"SSRM Warning"' "$file" | grep "^\.method" | tail -1)
        method_name=$(echo "$method_line" | awk '{print $3}')

        start_line=$(grep -n "^\.method.*${method_name}" "$file" | cut -d: -f1)
        end_line=$(awk -v start="$start_line" 'NR>start && /^\.end method/{print NR; exit}' "$file")

        if [ -n "$start_line" ] && [ -n "$end_line" ]; then
            {
                sed -n "1,$((start_line-1))p" "$file"
                sed -n "${start_line}p" "$file"
                echo "    .locals 1"
                echo ""
                echo "    const/4 v0, 0x0"
                echo ""
                echo "    return-void"
                sed -n "${end_line}p" "$file"
                sed -n "$((end_line+1)),\$p" "$file"
            } > "${file}.tmp"

            mv "${file}.tmp" "$file"
            echo "Patched: $file"
        fi
    fi
done
