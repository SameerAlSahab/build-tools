#!/bin/bash
#
#  Copyright (c) 2025 Sameer Al Sahab
#  Licensed under the MIT License. See LICENSE file for details.
#
#  Permission is hereby granted, free of charge, to any person obtaining a copy
#  of this software and associated documentation files (the "Software"), to deal
#  in the Software without restriction, including without limitation the rights
#  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#  copies of the Software, and to permit persons to whom the Software is
#  furnished to do so, subject to the following conditions:
#
#  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
#



EXTRACT_ROM() {
    mkdir -p "$WORKDIR"

    local targets=(
        "$MODEL:$CSC:main"
        "${EXTRA_MODEL:-}:$EXTRA_CSC:extra"
        "${STOCK_MODEL:-}:$STOCK_CSC:stock"
    )

    local processed=""

    for entry in "${targets[@]}"; do
        IFS=":" read -r m c type <<< "$entry"
        [[ -z "$m" || -z "$c" ]] && continue

        local fw_id="${m}_${c}"
        if [[ "$processed" =~ "$fw_id" ]]; then
            continue
        fi

        EXTRACT_FIRMWARE "$m" "$c" "$type" || return 1
        processed+="$fw_id "
    done

    return 0
}



EXTRACT_FIRMWARE() {
    local model=$1
    local csc=$2
    local fw_type=$3

    local odin_dir="${FW_BASE}/${model}_${csc}"
    local work_model="${WORKDIR}/${model}"
    UNPACK_CONF="${work_model}/unpack.conf"
    local target_partitions=(system product system_ext odm vendor_dlkm odm_dlkm system_dlkm vendor)


    LOG "Checking $fw_type firmware.."

    mkdir -p "$work_model"

    local ap_file
    ap_file=$(find "$odin_dir" -maxdepth 1 \( -name "AP_*.tar.md5" -o -name "AP_*.tar" \) | head -1)
    [[ -z "$ap_file" ]] && { ERROR_EXIT "AP package missing for $model"; return 1; }

    # Check if we need to extract or not
    local current_data
	
	# Samsung saves the md5 at the last of the file , so it takes a lot of time in low end machines, instead i thought to use inode+mtime verify. 
	# Remove # on _GET_MD5_HASH to verify with md5.
	
	#current_data=$(_GET_MD5_HASH "$ap_file")      
	current_data=$(_GET_FILE_STAT "$ap_file")
	
    if [[ -f "$UNPACK_CONF" ]]; then
        local cached_data
        cached_data=$(source "$UNPACK_CONF" && echo "$METADATA")

        if [[ "$cached_data" == "$current_data" && -f "${work_model}/.extraction_complete" ]]; then
            LOG_INFO "$model firmware already extracted."
            return 0
        fi
    fi


    LOG_INFO "Unpacking $model firmware.."


    rm -rf "${work_model:?}"/*
    mkdir -p "$work_model"

    local super_img="${work_model}/super.img"

    FETCH_FILE "$ap_file" "super.img" "$work_model" >/dev/null || {
        rm -f "$UNPACK_CONF" "${work_model}/.extraction_complete"
        ERROR_EXIT "Failed to extract super.img from $ap_file"
        return 1
    }

    if IS_GITHUB_ACTIONS; then
        rm -rf "$odin_dir"
    fi

    [[ ! -f "$super_img" ]] && {
        rm -f "$UNPACK_CONF" "${work_model}/.extraction_complete"
        ERROR_EXIT "super.img not found after extraction"
        return 1
    }

    # https://source.android.com/docs/core/ota/sparse_images
    if file "$super_img" | grep -q "sparse"; then
        local super_raw="${work_model}/super.raw"
        RUN_CMD "Converting sparse image" \
            "\"$BIN/android-tools/simg2img\" \"$super_img\" \"$super_raw\" >/dev/null" || {
            rm -f "$UNPACK_CONF" "${work_model}/.extraction_complete"
            ERROR_EXIT "sparse image to raw conversion failed"
        }
        rm -f "$super_img"
        super_img="$super_raw"
    fi

    #https://source.android.com/docs/core/ota/dynamic_partitions
    if [[ ! -f "$UNPACK_CONF" ]]; then
        local lpdump_output
        lpdump_output=$("$BIN/android-tools/lpdump" "$super_img" 2>&1) || {
            rm -f "$UNPACK_CONF" "${work_model}/.extraction_complete"
            ERROR_EXIT "lpdump failed for $model"
            return 1
        }

        local super_size metadata_size metadata_slots group_name group_size
        super_size=$(echo "$lpdump_output" | awk '/Partition name: super/,/Flags:/ {if ($1 == "Size:") {print $2; exit}}')
        metadata_size=$(echo "$lpdump_output" | awk '/Metadata max size:/ {print $4}')
        metadata_slots=$(echo "$lpdump_output" | awk '/Metadata slot count:/ {print $4}')

        read -r group_name group_size <<< $(echo "$lpdump_output" | awk '
            /Group table:/ {in_table=1}
            in_table && /Name:/ {name=$2}
            in_table && /Maximum size:/ {size=$3; if(size+0 > 0){print name, size; exit}}
        ')

        if [[ -n "$super_size" && -n "$group_name" ]]; then

		cat > "$UNPACK_CONF" <<EOF
METADATA="$current_data"
SUPER_SIZE="$super_size"
METADATA_SIZE="$metadata_size"
METADATA_SLOTS="$metadata_slots"
GROUP_NAME="$group_name"
GROUP_SIZE="$group_size"
EXTRACT_DATE="$(date '+%Y-%m-%d %H:%M:%S')"
PARTITIONS=""
FILESYSTEM="$fstype"
EOF
        else
            LOG_WARN "Incomplete super metadata for $model"
        fi
    fi

    "$BIN/android-tools/lpunpack" "$super_img" "$work_model/" || {
        rm -f "$UNPACK_CONF" "${work_model}/.extraction_complete"
        ERROR_EXIT "Failed to extract partitions from $model"
        return 1
    }
    LOG_END "Partitions unpacked"

    rm -f "$super_img"

    local found_count=0
    for part in "${target_partitions[@]}"; do
    
        #https://source.android.com/docs/core/ota/ab
        for suffix in "_a" ""; do
            local src_img="${work_model}/${part}${suffix}.img"
            local dst_img="${work_model}/${part}.img"

            if [[ -f "$src_img" ]]; then
                [[ "$src_img" != "$dst_img" ]] && mv -f "$src_img" "$dst_img"

                UNPACK_PARTITION "$dst_img" "$model" || {
                    rm -f "$UNPACK_CONF" "${work_model}/.extraction_complete"
                    return 1
                }

                rm -f "$dst_img"
                ((found_count++))
                break
            fi
        done
    done

    # Remove empty B slots (Virtual A/B)
    find "$work_model" -maxdepth 1 -type f -name "*_b.img" -delete

    [[ $found_count -eq 0 ]] && {
        rm -f "$UNPACK_CONF" "${work_model}/.extraction_complete"
        ERROR_EXIT "No valid partitions found for $model"
        return 1
    }

    # Put marker to skip next time.
    touch "${work_model}/.extraction_complete"

    
if [[ -n "${SUDO_USER:-}" ]]; then
    chown -R "$SUDO_USER:$SUDO_USER" "$WORKDIR"
    chmod -R 755 "$WORKDIR"
fi

    LOG_END "Unpacked $model firmware. ( Got $found_count partitions)"

    return 0
}




#
# Detect filesystem type of partition images
#
# Uses magic numbers and blkid for reliable filesystem detection
# EROFS: 0xE0F5E1E2 (Linux 5.4+ read-only filesystem)
# F2FS:  0x1020F5F2 (Flash-Friendly File System)
# EXT4:  0x53EF at offset 1080 (Standard Linux filesystem)
#

DETECT_FILESYSTEM() {
    local image_path="$1"
    [[ ! -f "$image_path" ]] && echo "unknown" && return 1

    # EROFS magic number (offset 1024)
    if [[ "$(xxd -p -l 4 -s 1024 "$image_path" 2>/dev/null)" == "e0f5e1e2" ]]; then
        echo "erofs"
        return 0
    fi

    # F2FS magic number (offset 1024)
    if [[ "$(xxd -p -l 4 -s 1024 "$image_path" 2>/dev/null)" == "1020f5f2" ]]; then
        echo "f2fs"
        return 0
    fi

    # EXT4 magic number (offset 1080)
    if [[ "$(xxd -p -l 2 -s 1080 "$image_path" 2>/dev/null)" == "53ef" ]]; then
        echo "ext4"
        return 0
    fi

    # Fallback to blkid for other filesystems
    local fstype
    fstype=$(blkid -o value -s TYPE "$image_path" 2>/dev/null)
    if [[ -n "$fstype" ]]; then
        echo "$fstype"
        return 0
    fi

    echo "unknown"
    ERROR_EXIT "Unknown filesystem: $image_path"

}

#
# Unpack individual partition images and generate config files
#
# Mounts images using appropriate tools (fuse.erofs for EROFS, mount for EXT4)
# Generates fs_config (UID/GID/permissions) and file_contexts (SELinux labels)
#

UNPACK_PARTITION() {
    local image_path=$1
    local model_name=$2
    local partition_name=$(basename "$image_path" .img)
    local fstype=$(DETECT_FILESYSTEM "$image_path")
    local model_workdir="${WORKDIR}/${model_name}"
    local config_out_dir="$model_workdir/config"
    local partition_out_dir="$model_workdir/$partition_name"
    local fs_config_file="$config_out_dir/${partition_name}_fs_config"
    local file_contexts_file="$config_out_dir/${partition_name}_file_contexts"
    local tmp_mount_dir=""
    UNPACK_CONF="$model_workdir/unpack.conf"

    [[ ! -f "$image_path" ]] && ERROR_EXIT "Image not found: $image_path" && return 1


    rm -rf "$ASTROROM/out"
    mkdir -p "$config_out_dir"

    LOG_INFO "Extracting $partition_name "


    [[ -d "$partition_out_dir" ]] && rm -rf "$partition_out_dir"
    rm -f "$fs_config_file" "$file_contexts_file"
    mkdir -p "$partition_out_dir"


    tmp_mount_dir=$(mktemp -d)
    trap 'umount "$tmp_mount_dir" &>/dev/null; fusermount -u "$tmp_mount_dir" &>/dev/null; rm -rf "$tmp_mount_dir"' RETURN


case $fstype in
    ext4|f2fs)
            mount -o ro "$image_path" "$tmp_mount_dir" >/dev/null || {
            ERROR_EXIT "EXT4 mount failed for $partition_name"
            return 1
        }
        ;;
    erofs)
            "$BIN/erofs-utils/fuse.erofs" "$image_path" "$tmp_mount_dir" 2> >(grep -v '^<W>' >&2) >/dev/null || {
            ERROR_EXIT "EROFS mount failed for $partition_name"
            return 1
        }
        ;;
    *)
        ERROR_EXIT "Unsupported filesystem: $fstype"
        return 1
        ;;
esac


        cp -a -T "$tmp_mount_dir" "$partition_out_dir" || {
        ERROR_EXIT "Cannot copy files to unpack directory for $partition_name"
        return 1
    }



#https://source.android.com/docs/security/features/selinux/implement
#https://source.android.com/docs/security/features/selinux
    LOG_INFO "Extracting links, modes & attrs from $partition_name"
    echo

    # Generate fs_config: UID, GID, permissions, capabilities
    # Format: <path> <uid> <gid> <mode> capabilities=<capability_mask>
    find "$tmp_mount_dir" | xargs stat -c "%n %u %g %a capabilities=0x0" > "$fs_config_file" || {
        ERROR_EXIT "Cannot generate file config for $partition_name"
        return 1
    }

    # Generate file_contexts: SELinux security contexts
    # Format: <path> <selinux_context>
    find "$tmp_mount_dir" | xargs -I {} sh -c 'echo "{} $(getfattr -n security.selinux --only-values -h --absolute-names "{}")"' sh > "$file_contexts_file" || {
        ERROR_EXIT "Cannot generate file contexts for $partition_name"
        return 1
    }


	sort -o "$fs_config_file" "$fs_config_file" 2>/dev/null
	sort -o "$file_contexts_file" "$file_contexts_file" 2>/dev/null


    if [[ "$partition_name" == "system" ]] && [[ -d "$partition_out_dir/system" ]]; then

        # System-as-root layout [/] | https://source.android.com/docs/core/architecture/partitions/system-as-root
        sed -i -e "s|$tmp_mount_dir |/ |g" -e "s|$tmp_mount_dir||g" "$file_contexts_file"
        sed -i -e "s|$tmp_mount_dir | |g" -e "s|$tmp_mount_dir/||g" "$fs_config_file"
    else
        # Other normal partition layout [partition_name/]
        sed -i "s|$tmp_mount_dir|/$partition_name|g" "$file_contexts_file"
        sed -i -e "s|$tmp_mount_dir | |g" -e "s|$tmp_mount_dir|$partition_name|g" "$fs_config_file"
        sed -i '1s|^|/ |' "$fs_config_file"
    fi

    # Escape regex metacharacters
    sed -i -E 's/([][()+*.^$?\\|])/\\\1/g' "$file_contexts_file"


while read -r line; do
    path=$(echo "$line" | awk '{print $1}')
    real_cap=$(_GET_CAPABILITIES_HEX "$path")


    if [[ "$real_cap" != "0x0" ]]; then

        escaped_path=$(echo "$path" | sed 's|/|\\/|g')
        sed -i "s|^$escaped_path .*capabilities=0x0|$line capabilities=$real_cap|" "$fs_config_file"
    fi
	
	done < <(find "$tmp_mount_dir" -type f)


    sed -i "/^PARTITIONS=/s/\"$/ $partition_name\"/" "$UNPACK_CONF"
    sed -i '/^PARTITIONS=/s/=" /="/' "$UNPACK_CONF"


    if ! grep -q "^FILESYSTEM=" "$UNPACK_CONF"; then
        echo "FILESYSTEM=\"$fstype\"" >> "$UNPACK_CONF"
    fi

    return 0
}


#
# Extracts the security.capability xattr and converts it to the fs_config hex format.
# $1: The path to the mounted file.
# Returns: The capability in 0xXX format, or 0x0 if not found.
#

_GET_CAPABILITIES_HEX() {
    local file_path="$1"
    local cap_raw cap_hex cap_int

    # Default
    echo "0x0" >/tmp/.cap_dummy


    {
        cap_raw=$(getfattr -n security.capability --only-values -h --absolute-names "$file_path")

        [[ -z "$cap_raw" ]] && { echo "0x0"; return; }

        # Detect base64 vs raw
        if [[ "$cap_raw" =~ [^[:alnum:]+/=] ]]; then
            cap_hex=$(echo -n "$cap_raw" | head -c 4 | xxd -p | tr -d '\n')
        else
            cap_hex=$(echo "$cap_raw" | base64 --decode | head -c 4 | xxd -p | tr -d '\n')
        fi

        [[ -z "$cap_hex" ]] && { echo "0x0"; return; }

        cap_int="0x$(echo "$cap_hex" | sed 's/\(..\)/\1 /g' | tac | tr -d ' ')"

        [[ ! "$cap_int" =~ ^0x[0-9a-fA-F]+$ ]] && cap_int="0x0"

        # Android only cares about run-as (CAP_SETUID | CAP_SETGID)
        if [[ "$cap_int" == "0x000000c0" ]]; then
            echo "0xc0"
        else
            echo "0x0"
        fi
    } 2>/dev/null
}
