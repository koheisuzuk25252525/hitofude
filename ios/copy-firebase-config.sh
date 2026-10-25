#!/bin/sh
set -eu
# This owner-specific file is optional and deliberately not a PBX resource reference.
config="$SRCROOT/Configuration/GoogleService-Info.plist"
destination="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
mkdir -p "$destination"
if [ -f "$config" ]; then
    /usr/bin/plutil -lint "$config" >/dev/null
    bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :BUNDLE_ID' "$config")
    if [ "$bundle_id" != "$PRODUCT_BUNDLE_IDENTIFIER" ]; then
        echo 'error: GoogleService-Info.plistのBUNDLE_IDとアプリのBundle Identifierをそろえてください。'
        exit 1
    fi
    cp "$config" "$destination/GoogleService-Info.plist"
else
    # Do not retain a previous build's configuration when the owner removes the file.
    rm -f "$destination/GoogleService-Info.plist"
fi
