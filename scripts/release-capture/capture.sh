#!/usr/bin/env bash
# Real native screenshots from a disposable checkout of the exact release source.
set -euo pipefail

capture_source="${1:?source checkout required}"
capture_family="${2:?iphone or ipad required}"
capture_output="${3:?output directory required}"
capture_tools="$(cd "$(dirname "$0")" && pwd)"
capture_commit="a04cd41237d4d74b382222aec60ad6c970fda8e2"
capture_bundle="com.koheisuzuk25252525.hitofude"
mkdir -p "$capture_output"
capture_source="$(cd "$capture_source" && pwd)"
capture_output="$(cd "$capture_output" && pwd)"
test "$(git -C "$capture_source" rev-parse HEAD)" = "$capture_commit"
test -z "$(git -C "$capture_source" status --porcelain -- ios/Hitofude)"

python3 "$capture_tools/prepare_capture.py" "$capture_source" "$capture_output"
xcodebuild -version > "$capture_output/xcode-version.txt"
xcrun simctl list --json > "$capture_output/simulators.json"
python3 - "$capture_output/simulators.json" "$capture_family" > "$capture_output/device-choice.txt" <<'PY'
import json, sys
data=json.load(open(sys.argv[1]))
family=sys.argv[2]
assert family in ('iphone','ipad')
available=[r for r in data['runtimes'] if r.get('isAvailable') and '.iOS-' in r['identifier']]
assert available, 'No available iOS Simulator runtime'
types={device['name']:device for device in data['devicetypes']}
choices=[]
for runtime in available:
    for device in data['devices'].get(runtime['identifier'],[]):
        if not device.get('isAvailable') or device['name'] not in types: continue
        matches=(device['name'].startswith('iPhone') and 'Pro Max' in device['name']) if family=='iphone' else (device['name'].startswith('iPad Pro') and '13-inch' in device['name'])
        if matches: choices.append((runtime,types[device['name']]))
assert choices, 'No available required large-display Simulator device/runtime pair'
runtime,device=max(choices,key=lambda pair:(tuple(int(n) for n in pair[0]['version'].split('.')),pair[1]['name']))
print(device['identifier'])
print(runtime['identifier'])
print(device['name'])
print(runtime['version'])
PY
capture_type="$(sed -n '1p' "$capture_output/device-choice.txt")"
capture_runtime="$(sed -n '2p' "$capture_output/device-choice.txt")"
echo "::notice title=Native capture device::$(sed -n '3p' "$capture_output/device-choice.txt"), iOS $(sed -n '4p' "$capture_output/device-choice.txt") ($capture_family)."
capture_device="$(xcrun simctl create "Hitofude 1.0-6 Release Capture $capture_family" "$capture_type" "$capture_runtime")"
printf '%s\n' "$capture_device" > "$capture_output/device-uuid.txt"
trap 'xcrun simctl shutdown "$capture_device" >/dev/null 2>&1 || true; xcrun simctl delete "$capture_device" >/dev/null 2>&1 || true' EXIT
capture_derived="$capture_output/DerivedData"
capture_destination="platform=iOS Simulator,id=$capture_device,arch=$(uname -m)"

cd "$capture_source"
echo "::notice title=Native capture phase::Building the unchanged release application and temporary UI-test target ($capture_family)."
xcodebuild -project ios/Hitofude.xcodeproj -scheme ReleaseCapture \
  -configuration Release -destination "$capture_destination" \
  -derivedDataPath "$capture_derived" CODE_SIGNING_ALLOWED=NO \
  build-for-testing 2>&1 | tee "$capture_output/build.log"
echo "::notice title=Native capture phase::Release Simulator build succeeded ($capture_family). Preparing the dedicated capture device."

xcrun simctl boot "$capture_device"
xcrun simctl bootstatus "$capture_device" -b
echo "::notice title=Native capture phase::Dedicated Simulator booted ($capture_family). Installing version 1.0 build 6."
capture_app="$capture_derived/Build/Products/Release-iphonesimulator/Hitofude.app"
test -d "$capture_app"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$capture_app/Info.plist")" = "1.0"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$capture_app/Info.plist")" = "6"
xcrun simctl install "$capture_device" "$capture_app"
capture_container="$(xcrun simctl get_app_container "$capture_device" "$capture_bundle" data)"
xcrun simctl shutdown "$capture_device"
mkdir -p "$capture_container/Library/Preferences"
cp "$capture_output/capture-fixture.plist" "$capture_container/Library/Preferences/$capture_bundle.plist"
xcrun simctl boot "$capture_device"
xcrun simctl bootstatus "$capture_device" -b
xcrun simctl ui "$capture_device" appearance light
xcrun simctl status_bar "$capture_device" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100

echo "::notice title=Native capture phase::Starting real UI taps and screenshot capture ($capture_family)."
set +e
xcodebuild -project ios/Hitofude.xcodeproj -scheme ReleaseCapture \
  -configuration Release -destination "$capture_destination" \
  -derivedDataPath "$capture_derived" -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 180 \
  -maximum-test-execution-time-allowance 180 \
  -resultBundlePath "$capture_output/Capture.xcresult" \
  CODE_SIGNING_ALLOWED=NO test-without-building 2>&1 | tee "$capture_output/test.log"
capture_test_status=${PIPESTATUS[0]}
set -e
echo "::notice title=Native capture phase::UI test process finished with status $capture_test_status ($capture_family). Exporting actual screenshot attachments."

if test -d "$capture_output/Capture.xcresult"; then
  xcrun xcresulttool export attachments --path "$capture_output/Capture.xcresult" \
    --output-path "$capture_output/screenshots" || true
fi
# Application implementation and resources must remain byte-for-byte identical.
git diff --exit-code "$capture_commit" -- ios/Hitofude
python3 - "$capture_output" "$capture_family" "$capture_test_status" <<'PY'
import hashlib,json,pathlib,re,shutil,struct,sys
out=pathlib.Path(sys.argv[1]); family=sys.argv[2]; passed=sys.argv[3]=='0'
images=[]
for file in sorted((out/'screenshots').rglob('*.png')):
    data=file.read_bytes()
    if data[:8]!=b'\x89PNG\r\n\x1a\n': continue
    width,height=struct.unpack('>II',data[16:24])
    images.append({'file':str(file.relative_to(out)),'width':width,'height':height,'alpha_channel':data[25] in (4,6),'sha256':hashlib.sha256(data).hexdigest()})
# Preserve original screenshot bytes while adding human-readable filenames if
# xcresulttool supplies an attachment manifest on this Xcode version.
named=[]
def visit(value):
    if isinstance(value,dict):
        exported=value.get('exportedFileName')
        suggested=value.get('suggestedHumanReadableName',value.get('name',''))
        match=re.search(r'(0[123]-(?:gameplay|completion|next-puzzle))',suggested)
        if exported and match:
            candidates=list((out/'screenshots').rglob(pathlib.Path(exported).name))
            if candidates and candidates[0].suffix.lower()=='.png':
                destination=out/'store-candidates'/f'{family}-{match.group(1)}.png'
                destination.parent.mkdir(exist_ok=True)
                shutil.copy2(candidates[0],destination)
                named.append(str(destination.relative_to(out)))
        for child in value.values(): visit(child)
    elif isinstance(value,list):
        for child in value: visit(child)
for file in (out/'screenshots').rglob('manifest.json'):
    visit(json.loads(file.read_text()))
manifest=json.loads((out/'capture-provenance.json').read_text())
manifest.update({'device_family':family,'device':(out/'device-choice.txt').read_text().splitlines(),'ui_tests_succeeded':passed,'images':images,'readable_copies':named})
(out/'capture-provenance.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
summary={'family':family,'ui_tests_succeeded':passed,'png_count':len(images),'dimensions':sorted({(i['width'],i['height']) for i in images}),'readable_copies':named,'alpha_channel_present':any(i['alpha_channel'] for i in images),'visual_review':'not performed by this script'}
(out/'screenshot-summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2))
print(json.dumps(summary))
if len(images)<3: raise SystemExit('Expected at least three actual UI screenshot attachments')
if any(i['width']<=0 or i['height']<=i['width'] for i in images):
    raise SystemExit('Unexpected portrait screenshot dimensions')
PY
exit "$capture_test_status"
