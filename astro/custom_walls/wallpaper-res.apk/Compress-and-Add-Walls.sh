#!/bin/bash

# Static wallpaper Settings
TARGET_RES_IMG="3200"
# Video Wallpaper settings
TARGET_FPS="60"
VIDEO_RES=1080
SCALE_FACTOR="0.5"


BASE_DIR="$(pwd)"
RES_DIR="$BASE_DIR/res"
DRAWABLE_DIR="$RES_DIR/drawable-nodpi"
RAW_DIR="$RES_DIR/raw"
JSON_MAIN="$RAW_DIR/resources_info.json"
JSON_FEATURE="$RAW_DIR/resources_info_feature.json"
CUSTOM_DIR="$PROJECT_DIR/custom_walls/res"


for cmd in jq ffmpeg cwebp bc; do
    if ! command -v $cmd &> /dev/null; then
        echo "Error: $cmd is missing."
        exit 1
    fi
done

echo "Scaling images..."
shopt -s globstar nullglob
for img in "$RES_DIR"/**/*.webp; do
    cwebp -q 90 "$img" -o "${img}.tmp" 2>/dev/null
    
    if [[ -f "${img}.tmp" ]]; then
        mv -f "${img}.tmp" "$img"
    fi
done
shopt -u globstar nullglob



echo "Scaling stock videos to $TARGET_FPS FPS"

shopt -s nullglob

for vid in "$RAW_DIR/video_"*.mp4; do
    if ffmpeg -y -i "$vid" \
  -vf "fps=$TARGET_FPS,scale=$VIDEO_RES:-2,setsar=1:1" \
  -c:v libx264 \
  -pix_fmt yuv420p \
  -profile:v high \
  -level 4.1 \
  -preset slow \
  -crf 23 \
  -g $TARGET_FPS \
  -keyint_min $TARGET_FPS \
  -sc_threshold 0 \
  -vsync cfr \
  -movflags +faststart \
  -c:a copy \
  "$vid.tmp.mp4" >/dev/null 2>&1; then

        mv -f "$vid.tmp.mp4" "$vid"
    else
        rm -f "$vid.tmp.mp4"
        ERROR_EXIT "Failed to scale $vid"
    fi
done

shopt -u nullglob

if grep -q "InfinityWallpaper" "$JSON_MAIN"; then

tmp_json=$(mktemp)

# Example
# "AOD AOD 0 300 1200 0.17 0.17 0.1 1"
# Format: [FROM] [TO] [START_FRAME] [END_FRAME] [duration] [easing values...]

jq --arg scale "$SCALE_FACTOR" '
    ($scale | tonumber) as $s |
    .phone |= map(
        if .type == 10 and (.filename // "" | startswith("video_")) then
            .frame_no = ((.frame_no // 0) * $s | floor) |
            if .type_params.service_settings then
                .type_params.service_settings |= (
                    .thumbnail_system_frame_no = ((.thumbnail_system_frame_no // 0) * $s | floor) |
                    .thumbnail_lock_frame_no = ((.thumbnail_lock_frame_no // 0) * $s | floor) |
                    .thumbnail_frame_no = ((.thumbnail_frame_no // 0) * $s | floor) |
                    .transition_frame_info = (
                        (.transition_frame_info // "") | split("\n") | map(
                            split(" ") | 
                            if length >= 4 then
                                .[2] = ((.[2] | tonumber) * $s | floor | tostring) |
                                .[3] = ((.[3] | tonumber) * $s | floor | tostring)
                            else . end | join(" ")
                        ) | join("\n")
                    )
                )
            else . end
        else . end
    )
' "$JSON_MAIN" > "$tmp_json" && mv "$tmp_json" "$JSON_MAIN"

fi

if [ -d "$CUSTOM_DIR" ]; then
    echo "Adding custom wallpapers..."
    
   
    NEXT_INDEX=$(jq '[.phone[].index] | max + 1' "$JSON_MAIN")
    
    
    for img in "$CUSTOM_DIR"/*.{jpg,png,webp}; do
        [ -e "$img" ] || continue
        
        # Calculate next filename
        LAST_NUM=$(find "$DRAWABLE_DIR" -name "wallpaper_*.webp" | grep -oE '[0-9]+' | sort -rn | head -1)
        NEW_NUM=$(printf "%03d" $((10#$LAST_NUM + 1)))
        NEW_NAME="wallpaper_${NEW_NUM}.webp"
        
        cwebp -q 100 -resize 0 "$TARGET_RES_IMG" "$img" -o "$DRAWABLE_DIR/$NEW_NAME" 2>/dev/null
        
        # Add to main JSON
        tmp_json=$(mktemp)
        jq --argjson idx "$NEXT_INDEX" --arg fn "$NEW_NAME" \
           '.phone += [{"isDefault": false, "index": $idx, "which": 1, "screen": 0, "type": 0, "filename": $fn, "frame_no": -1, "desc_str_id": "str_id_custom", "cmf_info": ["custom"]}]' \
           "$JSON_MAIN" > "$tmp_json" && mv "$tmp_json" "$JSON_MAIN"
        
        # Add to Recommendations (May require DressRoom Patches)
        if [ -f "$JSON_FEATURE" ]; then
            FEAT_IDX=$(jq '[.feature[].index] | max + 1' "$JSON_FEATURE")
            PRESET_ID=$(jq '[.feature[].preset_content_id | tonumber] | max + 1' "$JSON_FEATURE")
            
            jq --argjson idx "$FEAT_IDX" --arg pid "$PRESET_ID" --arg fn "$NEW_NAME" \
               '.feature += [{"index": $idx, "type": 0, "category": "feature_recommended", "filename": $fn, "preset_content_id": ($pid|tostring), "desc_str_id": "str_id_custom", "type_params": {}, "logging_info": {"custom_dimens": {"Featured": "Custom"}}}]' \
               "$JSON_FEATURE" > "$tmp_json" && mv "$tmp_json" "$JSON_FEATURE"
        fi
        
        echo "  Added: $NEW_NAME"
        NEXT_INDEX=$((NEXT_INDEX + 1))
    done

    
    for vid in "$CUSTOM_DIR"/*.mp4; do
        [ -e "$vid" ] || continue
        
        LAST_NUM=$(find "$RAW_DIR" -name "video_*.mp4" | grep -oE '[0-9]+' | sort -rn | head -1)
        NEW_NUM=$(printf "%03d" $((10#$LAST_NUM + 1)))
        NEW_NAME="video_${NEW_NUM}.mp4"
        
        # Encode
        ffmpeg -y -i "$vid" -c:v libx264 -c:a copy -crf 23 -r "$TARGET_FPS" -vf "scale=1080:-2" "$RAW_DIR/$NEW_NAME" 2>/dev/null
        
        # Calculate frames for JSON
        FRAMES=$(ffprobe -v error -select_streams v:0 -count_frames -show_entries stream=nb_read_frames -of csv=p=0 "$RAW_DIR/$NEW_NAME")
        HALF_FRAMES=$((FRAMES / 2))
        
        # Add to main JSON
        tmp_json=$(mktemp)
        jq --argjson idx "$NEXT_INDEX" --arg fn "$NEW_NAME" --argjson f "$FRAMES" --argjson hf "$HALF_FRAMES" \
           '.phone += [{"isDefault": false, "index": $idx, "which": 7, "screen": 0, "target_screen_only": true, "type": 10, "type_params": {"content_type": "infinity", "service_package_name": "com.samsung.android.wallpaper.live", "service_class_name": "com.samsung.android.wallpaper.live.infinity.InfinityWallpaper", "service_settings": {"filename": $fn, "thumbnail_system_frame_no": $f, "thumbnail_lock_frame_no": $hf, "thumbnail_frame_no": $hf, "transition_frame_info": ("AOD HOME 0 " + ($f|tostring) + " 1000 0.33 0 0.1 1")}}, "filename": $fn, "frame_no": $f, "desc_str_id": "str_id_custom_video", "cmf_info": ["custom"]}]' \
           "$JSON_MAIN" > "$tmp_json" && mv "$tmp_json" "$JSON_MAIN"
           
        # Add to Features JSON
        if [ -f "$JSON_FEATURE" ]; then
            FEAT_IDX=$(jq '[.feature[].index] | max + 1' "$JSON_FEATURE")
            PRESET_ID=$(jq '[.feature[].preset_content_id | tonumber] | max + 1' "$JSON_FEATURE")
            
            jq --argjson idx "$FEAT_IDX" --arg pid "$PRESET_ID" --arg fn "$NEW_NAME" \
               '.feature += [{"index": $idx, "type": 10, "category": "feature_recommended", "filename": $fn, "preset_content_id": ($pid|tostring), "desc_str_id": "str_id_custom_video", "type_params": {}, "logging_info": {"custom_dimens": {"Featured": "CustomVideo"}}}]' \
               "$JSON_FEATURE" > "$tmp_json" && mv "$tmp_json" "$JSON_FEATURE"
        fi

        echo "  Added: $NEW_NAME"
        NEXT_INDEX=$((NEXT_INDEX + 1))
    done
fi

echo "Done."