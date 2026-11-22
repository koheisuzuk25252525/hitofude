# Native release screenshot capture

These verification tools operate on a **disposable copy** of release source `a04cd41237d4d74b382222aec60ad6c970fda8e2`. They do not change the application Swift source, resources, build number, signing, release branch, or App Store Connect settings.

1. `python3 scripts/release-capture/prepare_capture.py` adds only a temporary `ReleaseCaptureUITests` target and a `ReleaseCapture` scheme. It prepares a UserDefaults fixture from the actual bundled `5-easy` puzzle bank. The fixture is a valid unfinished game; completion is reached through real UI taps.
2. Build with `xcodebuild -project ios/Hitofude.xcodeproj -scheme ReleaseCapture -configuration Release -destination 'platform=iOS Simulator,id=DEVICE_UUID' -derivedDataPath DERIVED_DATA CODE_SIGNING_ALLOWED=NO build-for-testing`.
3. Boot a dedicated disposable Simulator, install `DERIVED_DATA/Build/Products/Release-iphonesimulator/Hitofude.app`, obtain its data container (`xcrun simctl get_app_container DEVICE_UUID com.koheisuzuk25252525.hitofude data`), then **shut down that Simulator**. Copy `capture-output/capture-fixture.plist` into `CONTAINER/Library/Preferences/com.koheisuzuk25252525.hitofude.plist`. Do not copy into a user's existing device or app container.
4. Boot it again, set light appearance (`xcrun simctl ui DEVICE_UUID appearance light`) and a clean status bar (`xcrun simctl status_bar DEVICE_UUID override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100`).
5. Run `xcodebuild ... -scheme ReleaseCapture -configuration Release -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -resultBundlePath CAPTURE.xcresult CODE_SIGNING_ALLOWED=NO test-without-building`. Disable test-device cloning with `-parallel-testing-enabled NO`; use the same explicit destination ID where the fixture was installed.
6. Export real PNG attachments with `xcrun xcresulttool export attachments --path CAPTURE.xcresult --output-path capture-output/DEVICE_NAME` (Xcode 16 or newer). Inspect actual pixel dimensions and the PNGs before uploading to App Store Connect.

Capture on a large iPhone and a 13-inch iPad Simulator. Retain `capture-provenance.json`, test result bundles, build log, and device/runtime list alongside screenshots. Screenshots are unedited native UI; fixture elapsed time is representative test data, not a real player's record.

These screenshots/test results are **Simulator evidence**, not verification of the signed TestFlight archive, physical touch/audio behavior, Universal Links on a real installed device, or ad delivery.

Do not check the generated app project, generated UI tests, fixture, or DerivedData into the release branch. Do not distribute the screenshot runner app.
