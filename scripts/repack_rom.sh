#!/usr/bin/env bash
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



REPACK_PARTITION() {
    local partition_name="$1"
    local target_fs="$2"
    local out_dir="$3"
    local model_fs_dir="$4"

    [[ ! -d "$model_fs_dir/$partition_name" ]] && {
        ERROR_EXIT "Partition folder not found in $model_fs_dir/$partition_name"
    }

    local UNPACK_CONF="$model_fs_dir/unpack.conf"
    local HEADROOM_PERCENT=7
    
    local foldersize_kb=$(du -s -k "$model_fs_dir/$partition_name" | awk '{print $1}')
    target_size_kb=$((foldersize_kb + foldersize_kb * HEADROOM_PERCENT / 100))

    if (( foldersize_kb < 15043 )); then
        target_size_kb=$((foldersize_kb + foldersize_kb * 35 / 100))
    else
        target_size_kb=$((foldersize_kb + foldersize_kb * HEADROOM_PERCENT / 100))
    fi
    
    # System-as-root partitions use "/" as their mount point
    local mount_point="/$partition_name"
    [[ "$partition_name" =~ ^system(_[ab])?$ ]] && mount_point="/"

  
    local config_path="$model_fs_dir/$partition_name"
    [[ "$partition_name" == "system" && -d "$model_fs_dir/system/system" ]] && config_path="$model_fs_dir/system/system"

    local fs_config="$model_fs_dir/config/${partition_name}_fs_config"
    local file_contexts="$model_fs_dir/config/${partition_name}_file_contexts"


    # Generate known missing config and context entries before building the image
    "$BIN/gen_config/gen_fsconfig" -t "$USABLE_THREADS" -p "$config_path" -c "$fs_config" -q >/dev/null 2>&1 || {
        echo
        ERROR_EXIT "Failed to generate missing configs for $partition_name"
    }

    "$BIN/gen_config/gen_file_contexts" -t "$USABLE_THREADS" -a -f "$target_fs" -p "$config_path" -c "$file_contexts" -q >/dev/null 2>&1 || {
        echo
        ERROR_EXIT "Failed to generate missing contexts for $partition_name"
    }

    # Remove duplicates and ensure known capabilities exist for consistency  
    for f in "$fs_config" "$file_contexts"; do
        awk '!seen[$0]++' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
        sed -i 's/\r//g; s/[^[:print:]]//g; /^$/d' "$f"
    done
    
    sed -i '/^[a-zA-Z0-9\/]/ { /capabilities=/! s/$/ capabilities=0x0/ }' "$fs_config"
    sed -i 's/  */ /g' "$fs_config"


    # https://source.android.com/docs/core/architecture/android-kernel-file-system-support
    case "$target_fs" in
        ext4)
            local block_count=$(( target_size_kb / 4 )) # ext4 block size is 4096 bytes

            # Workaround: ext4 requires a lost+found entry to be declared in configs
            if [[ "$mount_point" == "/" ]]; then
                grep -q "^/lost\+found " "$file_contexts" || echo "/lost\+found u:object_r:rootfs:s0" >> "$file_contexts"
                grep -q "^lost\+found " "$fs_config" || echo "lost+found 0 0 700 capabilities=0x0" >> "$fs_config"
            else
                grep -q "^/$partition_name/lost\+found " "$file_contexts" || echo "/$partition_name/lost\+found $(head -n 1 "$file_contexts" | awk '{print $2}')" >> "$file_contexts"
                grep -q "^$partition_name/lost\+found " "$fs_config" || echo "$partition_name/lost+found 0 0 700 capabilities=0x0" >> "$fs_config"
            fi

            # Build ext4 image using mke2fs, populate with e2fsdroid, and then make size minimium as possible.
            # https://android.googlesource.com/platform/prebuilts/fullsdk-linux/platform-tools/+/83a183b4bced4377eb5817074db82885cfcae393/e2fsdroid
            local build_cmd="
                $BIN/android-tools/mke2fs.android -t ext4 -b 4096 -L '$mount_point' -O ^has_journal '$out_dir/$partition_name.img' $block_count && \
                $BIN/android-tools/e2fsdroid -e -T 1230735600 -C '$fs_config' -S '$file_contexts' -a '$mount_point' -f '$model_fs_dir/$partition_name' '$out_dir/$partition_name.img' && \
                tune2fs -m 0 '$out_dir/$partition_name.img' && \
                e2fsck -fy '$out_dir/$partition_name.img' && \
                NEW_BLOCKS=\$(tune2fs -l '$out_dir/$partition_name.img' | awk '/Block count:/ {total=\$3} /Free blocks:/ {free=\$3} END { used=total-free; printf \"%d\", used + (used*0.01) + 10 }') && \
                resize2fs -f '$out_dir/$partition_name.img' \$NEW_BLOCKS && \
                truncate -s \$((NEW_BLOCKS * 4096)) '$out_dir/$partition_name.img'
            "

            RUN_CMD "Building ${partition_name} (ext4)" "$build_cmd" || return 1
       
            ;;

        erofs)
            # https://source.android.com/docs/core/architecture/kernel/erofs
            # Samsung uses a fixed timestamp for their erofs images.
            RUN_CMD "Building ${partition_name} (erofs)" \
                "$BIN/erofs-utils/mkfs.erofs -z 'lz4hc,9' -b 4096 -T 1640995200 --mount-point=$mount_point --fs-config-file=$fs_config --file-contexts=$file_contexts $out_dir/$partition_name.img $model_fs_dir/$partition_name/" || return 1
            ;;

        f2fs)
            # https://android.googlesource.com/platform/external/f2fs-tools/
            # F2FS requires more complex size calculation due to its internal structure and overhead.
            local base_size=$(du -sb "$model_fs_dir/$partition_name" | awk '{print $1}')
            local f2fs_overhead
            local final_margin_percent
            # TODO: Try make it minimium , as of now 56MB overhead+7% headroom
                f2fs_overhead=$((56 * 1024 * 1024))
                final_margin_percent=107

            local total_size=$(( (f2fs_overhead + base_size) * final_margin_percent / 100 ))
            local temp_img="$out_dir/${partition_name}_temp.img"

            # Create a blank image, format it as F2FS, then populate it with sload.f2fs
            # https://android.googlesource.com/platform/external/f2fs-tools/+/71313114a147ee3fc4a411904de02ea8b6bf7f91/Android.mk
            RUN_CMD "Building ${partition_name} (f2fs)" \
                "truncate -s $total_size $temp_img && \
                $BIN/android-tools/make_f2fs -f -O extra_attr,inode_checksum,sb_checksum,compression $temp_img && \
                $BIN/android-tools/sload_f2fs -f $model_fs_dir/$partition_name -C $fs_config -s $file_contexts -T 1640995200 -t $mount_point -c $temp_img -a lz4 -L 2 && \
                mv $temp_img $out_dir/$partition_name.img" || return 1
            ;;

        *)
            ERROR_EXIT "Unsupported filesystem: $target_fs"
            ;;
    esac
}


#
# Creates a super.img from individual partition images using lpmake.
#
BUILD_SUPER_IMAGE() {
    local out_dir="${DIROUT}"
    local conf_file="$MAIN_WORKSPACE/unpack.conf"
  
    [[ -f "$STOCK_FW/unpack.conf" ]] && conf_file="$STOCK_FW/unpack.conf"

    [[ ! -f "$conf_file" ]] && ERROR_EXIT "unpack.conf not found for super image generation. Make sure you have stock firmware unpacked."
    
    source "$conf_file"

    local valid_partitions=()
    local current_total_size=0

    for part in $PARTITIONS; do
        local img="$out_dir/${part}.img"
        if [[ -f "$img" ]]; then
            valid_partitions+=("$part")
            current_total_size=$(( current_total_size + $(stat -c%s "$img") ))
        fi
    done

    (( current_total_size > GROUP_SIZE )) && ERROR_EXIT "Partition sizes ($current_total_size) exceed group limit ($GROUP_SIZE). Please try to reduce size."

    # Build the argument list for lpmake
    # https://android.googlesource.com/platform/system/extras/+/master/partition_tools/
    local lp_args=(
        --device-size "$SUPER_SIZE"
        --metadata-size "$METADATA_SIZE"
        --metadata-slots "$METADATA_SLOTS"
        --group "$GROUP_NAME:$GROUP_SIZE"
        --output "$out_dir/super.img"
    )

    for part in "${valid_partitions[@]}"; do
        local p_size=$(stat -c%s "$out_dir/${part}.img")
        lp_args+=(--partition "${part}:readonly:${p_size}:${GROUP_NAME}")
        lp_args+=(--image "${part}=$out_dir/${part}.img")
    done

    RUN_CMD "Building super.img" "$BIN/android-tools/lpmake ${lp_args[*]}"

   
    for part in "${valid_partitions[@]}"; do
        rm -f "$out_dir/${part}.img"
    done
}

#
# Creates a flashable ZIP package from the super.img and an installer.
#

CREATE_FLASHABLE_ZIP() {
    local build_date=$(date +%Y%m%d)
    local name_prefix="AstroROM_${STOCK_MODEL}_v${ROM_VERSION}_${build_date}"
    local super_img="${DIROUT}/super.img"
    local build_dir="${DIROUT}/zip_build"
    local zip_path="$DIROUT/$name_prefix.zip"
    local signed_zip_path="${DIROUT}/${name_prefix}_signed.zip"


    [[ -f "$super_img" ]] || ERROR_EXIT "super.img missing."
    COMMAND_EXISTS "7z" || ERROR_EXIT "7z tool not found."
   
    rm -rf "$build_dir" && mkdir -p "$build_dir"

    
    cp -a "${BIN}/dynamic_installer"/. "$build_dir/"
    mv "$super_img" "$build_dir/super.img"

    # Customize the updater-script with build-specific variables
    local updater="$build_dir/META-INF/com/google/android/updater-script"
    if [[ -f "$updater" ]]; then

    sed -i \
        -e "s|__ROM_VERSION__|${ROM_VERSION}|g" \
        -e "s|__MODEL_NAME__|${MODEL_NAME}|g" \
        -e "s|__BUILD_DATE__|${build_date}|g" \
        -e "s|__CODENAME__|${CODENAME}|g" \
        "$updater"

    fi
    

if IS_GITHUB_ACTIONS; then
    COMPRESSION_LEVEL=6
else
    COMPRESSION_LEVEL=4
fi

    RUN_CMD "Building ROM zip" \
        "cd '$build_dir' && 7z a -tzip -mx=$COMPRESSION_LEVEL '$zip_path' ."


    rm -rf "$build_dir"


    LOG_END "Flashable zip created at $(basename "$zip_path")"
    
}


REPACK_ROM() {
    local target_fs="$1"
    local out_dir="${DIROUT}"

    if [[ -d "$out_dir" ]]; then
        rm -rf "$out_dir"/*
    else
        mkdir -p "$out_dir"
    fi

    for part_dir in "$WORKSPACE"/*/; do
        local name=$(basename "$part_dir")
      
        [[ "$name" =~ ^(config|lost\+found)$ ]] && continue

        REPACK_PARTITION "$name" "$target_fs" "$out_dir" "$WORKSPACE"
    done

    # Check if we should create a full zip or just the unpacked images for debugging. For instance , fastboot or recovery flash.
    if GET_FEAT_STATUS DEBUG_BUILD; then
        LOG_INFO "ROM debug build enabled. Repacked images are available at $DIROUT"
    else
        # For a release build, create the final flashable ZIP
        BUILD_SUPER_IMAGE
        CREATE_FLASHABLE_ZIP
    fi
}
