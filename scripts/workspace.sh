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


INIT_BUILD_ENV() {
    
    MAIN_WORKDIR="${WORKDIR}/${MODEL}"
    STOCK_WORKDIR="${WORKDIR}/${STOCK_MODEL:-$MODEL}"
    EXTRA_WORKDIR="${WORKDIR}/${EXTRA_MODEL}"

    EXTRACT_ROM || ERROR_EXIT "Firmware extraction failed."

    LOG_BEGIN "Creating final workspace"
    CREATE_WORKSPACE
}


CREATE_WORKSPACE() {
    local build_dir="$ASTROROM/workspace"
    local config_dir="$build_dir/config"
    local marker="$build_dir/.workspace"


    local b_date=$(GET_PROP "system" "ro.build.date" "main" 2>/dev/null || echo "unknown")
    local b_utc=$(GET_PROP "system" "ro.build.date.utc" "main" 2>/dev/null || echo "0")
    local b_ver=$(GET_PROP "system" "ro.build.version.release" "main" 2>/dev/null || echo "unknown")


    if [[ -f "$marker" ]]; then
        local old_port=$(grep "^PORT_MODEL=" "$marker" | cut -d= -f2)
        local old_date=$(grep "^BUILD_DATE=" "$marker" | cut -d= -f2)
        if [[ "$old_port" == "$MODEL" && "$old_date" == "$b_date" ]]; then
            LOG_INFO "Workspace is already set. Skipping rebuild."
            WORKSPACE="$build_dir"
            CONFIG_DIR="$config_dir"
            return 0
        fi
    fi

    rm -rf "$build_dir" && mkdir -p "$config_dir"


    local oem_parts=("vendor" "odm" "vendor_dlkm" "odm_dlkm" "system_dlkm")
    local port_parts=("system" "product" "system_ext")


    if [[ "$MODEL" == "$STOCK_MODEL" || -z "$STOCK_MODEL" ]]; then
        LINK_PARTITIONS "$MAIN_WORKDIR" "$build_dir" "$config_dir" "${port_parts[@]}" "${oem_parts[@]}"
    else
        LINK_PARTITIONS "$MAIN_WORKDIR" "$build_dir" "$config_dir" "${port_parts[@]}"
        LINK_PARTITIONS "$STOCK_WORKDIR" "$build_dir" "$config_dir" "${oem_parts[@]}"
    fi


    chown -R -h "$SUDO_USER:$SUDO_USER" "$build_dir" 2>/dev/null


    cat > "$marker" <<EOF
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
PORT_MODEL=$MODEL
STOCK_MODEL=${STOCK_MODEL}
EXTRA_MODEL=${EXTRA_MODEL:-None}
ANDROID_VERSION=$b_ver
BUILD_DATE=$b_date
BUILD_DATE_UTC=$b_utc
EOF

    WORKSPACE="$build_dir"
    CONFIG_DIR="$config_dir"

    LOG_INFO "Checking VNDK version..."

    [[ -z "$VNDK" ]] && { ERROR_EXIT "VNDK version not defined."; return 1; }
    local sys_ext_dir
    sys_ext_dir=$(GET_PARTITION_PATH "system_ext") || return 1

 
    local manifest="${sys_ext_dir}/etc/vintf/manifest.xml"
    local current_vndk=""

    if [[ -f "$manifest" ]]; then
        current_vndk=$(grep -A2 -i "vendor-ndk" "$manifest" | grep -oP '<version>\K[0-9]+' | head -1)
        [[ "$current_vndk" == "$VNDK" ]] && { LOG_END "VNDK matches ($VNDK)."; return 0; }
    fi

    LOG_WARN "VNDK mismatch (Current: ${current_vndk:-None} and Target: $VNDK). Patching..."

    local apex_name="com.android.vndk.v${VNDK}.apex"
    local source_apex="${PROJECT_DIR}/vndk/v${VNDK}/${apex_name}"
    local dest_rel_path="apex/${apex_name}"


    find "${sys_ext_dir}/apex" -name "com.android.vndk.v*.apex" -delete 2>/dev/null


    if ! ADD "system_ext" "$source_apex" "$dest_rel_path" "VNDK v${VNDK} APEX"; then
        ERROR_EXIT "Failed to install VNDK APEX."
        return 1
    fi

    # Update Manifest
    if [[ -f "$manifest" ]]; then
        if grep -q "<vendor-ndk>" "$manifest"; then
            sed -i "s|<version>[0-9]\+</version>|<version>${VNDK}</version>|g" "$manifest"
        else
            sed -i "s|</manifest>|    <vendor-ndk>\\n        <version>${VNDK}</version>\\n    </vendor-ndk>\\n</manifest>|" "$manifest"
        fi
        LOG_INFO "Manifest updated."
    fi

    LOG_END "VNDK patching completed."

    local stock_path ws_path
    local stock_layout="merged" ws_layout="merged"

   
    if stock_path=$(GET_PARTITION_PATH "system_ext" "stock" 2>/dev/null); then
        [[ "$stock_path" == *"/system_ext" ]] && [[ "$stock_path" != *"/system/system/system_ext" ]] && stock_layout="separate"
    fi

    
    if ws_path=$(GET_PARTITION_PATH "system_ext" 2>/dev/null); then
        [[ "$ws_path" == *"/system_ext" ]] && [[ "$ws_path" != *"/system/system/system_ext" ]] && ws_layout="separate"
    else
        return 0
    fi

    [[ "$ws_layout" == "$stock_layout" ]] && return 0

   
    local sys_config="${CONFIG_DIR}/system_fs_config"
    local sys_contexts="${CONFIG_DIR}/system_file_contexts"
    
    if [[ "$stock_layout" == "merged" ]]; then
      
        LOG_INFO "Merging system_ext into system..."
        local dest_dir="$WORKSPACE/system/system/system_ext"
        
        mkdir -p "$dest_dir"
        SUDO rsync -a --delete "${ws_path}/" "${dest_dir}/" || return 1
        SUDO rm -rf "$ws_path"
        
        
        SUDO ln -sf "/system/system_ext" "$WORKSPACE/system/system_ext"
        echo "system/system_ext 0 0 755 capabilities=0x0" >> "$sys_config"
        echo "/system_ext u:object_r:system_file:s0" >> "$sys_contexts"

    else
        
        LOG_INFO "Separating system_ext from system..."
        local dest_dir="$WORKSPACE/system_ext"
        
        mkdir -p "$dest_dir"
        SUDO rsync -a --delete "${ws_path}/" "${dest_dir}/" || return 1
        SUDO rm -rf "$ws_path"
        [[ -L "$WORKSPACE/system/system_ext" ]] && SUDO rm -f "$WORKSPACE/system/system_ext"

     
        echo "system_ext" > "${CONFIG_DIR}/system_ext_fs_config"
        sed -i '/^system\/system_ext/d' "$sys_config"
        sed -i '/^\/system\/system_ext/d' "$sys_contexts"
    fi

  
    local target="$WORKSPACE/${stock_layout:0:6}_ext" 
    [[ "$stock_layout" == "merged" ]] && target="$WORKSPACE/system/system/system_ext"
    [[ "$stock_layout" == "separate" ]] && target="$WORKSPACE/system_ext"


    LOG_END "Build environment ready at $build_dir"
}


LINK_PARTITIONS() {
    local src_dir="$1"
    local build_dir="$2"
    local config_dir="$3"
    shift 3
    local partitions=("$@")

    for part in "${partitions[@]}"; do
        local src_path="$src_dir/$part"
        local target_path="$build_dir/$part"

        [[ ! -d "$src_path" ]] && continue


        SUDO cp -al "$src_path" "$build_dir/" || ERROR_EXIT "Cannot process $part in workspace."


        SUDO find "$target_path" -type f \( \
            -name "*.prop" -o -name "*.xml" -o -name "*.conf" -o \
            -name "*.sh" -o -name "*.json" -o -name "*.rc" -o -size -1M \
        \) -exec sh -c 'cp --preserve=mode,timestamps "$1" "$1.tmp" && mv "$1.tmp" "$1"' _ {} \; 2>/dev/null

        SUDO chmod -R u+w "$target_path" 2>/dev/null


        for cfg_type in "fs_config" "file_contexts"; do
            local cfg_file="$src_dir/config/${part}_${cfg_type}"
            [[ -f "$cfg_file" ]] && cp -a "$cfg_file" "$config_dir/"
        done
    done
}


GET_PARTITION_PATH() {
    local partition_name="$1"
    local firmware_type="${2:-}"
    local base_dir


    if [[ -n "$firmware_type" ]]; then
        base_dir=$(GET_FW_DIR "$firmware_type")
        if [[ -z "$base_dir" ]]; then
            ERROR_EXIT "Unknown firmware type '$firmware_type'" >&2
        fi
    else

        base_dir="${WORKSPACE}"
    fi


    local target_dir
    case "$partition_name" in
        system)

            if [[ -d "${base_dir}/system/system" ]]; then
                target_dir="${base_dir}/system/system"
            else
                target_dir="${base_dir}/system"
            fi
            ;;
        system_ext)
            local system_ext_path
            system_ext_path=$(FIND_SYSTEM_EXT "$base_dir" 2>/dev/null)
            if [[ -n "$system_ext_path" ]]; then
                target_dir="$system_ext_path"
            else
                LOG_WARN "Could not get system_ext in $base_dir" >&2
                return 1
            fi
            ;;
        *)
            target_dir="${base_dir}/${partition_name}"
            ;;
    esac


    if [[ ! -d "$target_dir" ]]; then
        LOG_WARN "Partition directory '$partition_name' not found in $base_dir" >&2
        return 1
    fi

    echo "$target_dir"
    return 0
}



FIND_SYSTEM_EXT() {
    local workspace="$1"

    if [[ -d "$workspace/system_ext" ]]; then
        echo "$workspace/system_ext"
        return 0
    elif [[ -d "$workspace/system/system/system_ext" ]]; then
        echo "$workspace/system/system/system_ext"
        return 0
    elif [[ -d "$workspace/system_a/system/system/system_ext" ]]; then
        echo "$workspace/system_a/system/system/system_ext"
        return 0
    fi

    return 1
}


GET_FW_DIR() {
    local source_firmware="$1"
    
    case "$source_firmware" in
        "main")  echo "$MAIN_WORKDIR" ;;
        "extra") echo "$EXTRA_WORKDIR" ;;
        "stock") echo "$STOCK_WORKDIR" ;;
        *)
        
            local blob_source="$BLOBS_DIR/$source_firmware"
            if [[ -d "$blob_source" ]]; then
                echo "$blob_source"
            else
                return 1
            fi
            ;;
    esac
    return 0
}


VALIDATE_WORKDIR() {
    local source_firmware="$1"
    local workdir

    workdir=$(GET_FW_DIR "$source_firmware" 2>/dev/null) || {
        return 1
    }

    if [[ ! -d "$workdir" ]]; then
        LOG_WARN "Work directory does not exist for '$source_firmware': $workdir"
        return 1
    fi

    if [[ -z "$(ls -A "$workdir" 2>/dev/null)" ]]; then
        LOG_WARN "Work directory is empty for '$source_firmware': $workdir"
        return 1
    fi

    return 0
}

