#!/usr/bin/env python3
"""Add a verification-only UI test target to a disposable checkout.

No application Swift, resources, version, signing, or release branch is changed.
Run from the repository root on the macOS CI runner before build-for-testing.
"""
import hashlib
import json
import pathlib
import plistlib
import subprocess
import sys
import xml.etree.ElementTree as ET

TOOLS = pathlib.Path(__file__).resolve().parent
ROOT = pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else TOOLS.parents[1]
OUT = pathlib.Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else ROOT / "capture-output"
OUT.mkdir(parents=True, exist_ok=True)
project = ROOT / "ios/Hitofude.xcodeproj/project.pbxproj"
original = project.read_text()
if "ReleaseCaptureUITests" in original:
    raise SystemExit("Use a fresh checkout: capture target already exists")

# Use an actual shipping puzzle and its original seed, rather than a mock board.
javascript = """
const fs = require('node:fs'), vm = require('node:vm');
const context = vm.createContext({});
vm.runInContext(fs.readFileSync('ios/Hitofude/Resources/Generator.js', 'utf8'), context);
process.stdout.write(vm.runInContext("JSON.stringify(preparedPuzzles['5-easy'][0])", context));
"""
entry = json.loads(subprocess.check_output(["node", "-e", javascript], cwd=ROOT))
puzzle = entry["puzzle"]
path = puzzle["path"]
assert len(path) == 25 and len({(c["row"], c["column"]) for c in path}) == 25
assert all(abs(a["row"] - b["row"]) + abs(a["column"] - b["column"]) == 1 for a, b in zip(path, path[1:]))
# Swift encodes Dictionary<Cell, Int> as an alternating key/value array.
swift_puzzle = dict(puzzle)
swift_puzzle["clues"] = [item for clue in puzzle["clues"] for item in ({"row": clue["row"], "column": clue["column"]}, clue["value"])]
prefix_count = 7
session = {
    "attemptID": "C5C31DBB-F4A7-4892-9666-FA7CE3DA58DD",
    "version": 1, "mode": "easy", "seed": entry["seed"],
    "puzzle": swift_puzzle, "route": path[:prefix_count], "hintsLeft": 3,
    "superHintUnlocked": False, "guidedIndices": [], "elapsed": 38,
    "hasStarted": True, "isFinished": False,
}
fixture = {
    "hitofude.onboarding.v2.stage": json.dumps({"stage": 2, "progress": 0}).encode(),
    "hitofude.tutorialCompleted": True,
    "hitofude.session.v1": json.dumps(session, separators=(",", ":")).encode(),
    "AppleLanguages": ["ja"], "AppleLocale": "ja_JP",
}
(OUT / "capture-fixture.plist").write_bytes(plistlib.dumps(fixture))
(OUT / "capture-puzzle.json").write_text(json.dumps(entry, ensure_ascii=False, indent=2))

source = (TOOLS / "ReleaseCaptureUITests.swift.template").read_text()
source = source.replace("__REMAINING_CELLS__", ",\n            ".join(f"({c['row'] + 1}, {c['column'] + 1})" for c in path[prefix_count:]))
test_dir = ROOT / "ios/ReleaseCaptureUITests"
test_dir.mkdir()
(test_dir / "ReleaseCaptureUITests.swift").write_text(source)

objects = '''
 F90000000000000000000001 = {isa = PBXNativeTarget; buildConfigurationList = F90000000000000000000002; buildPhases = (F90000000000000000000005, F90000000000000000000006, F90000000000000000000007); buildRules = (); dependencies = (A00000000000000000000040); name = ReleaseCaptureUITests; productName = ReleaseCaptureUITests; productReference = F90000000000000000000008; productType = "com.apple.product-type.bundle.ui-testing";};
 F90000000000000000000002 = {isa = XCConfigurationList; buildConfigurations = (F90000000000000000000003, F90000000000000000000004); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;};
 F90000000000000000000003 = {isa = XCBuildConfiguration; name = Debug; buildSettings = {CODE_SIGNING_ALLOWED = NO; CODE_SIGNING_REQUIRED = NO; GENERATE_INFOPLIST_FILE = YES; PRODUCT_BUNDLE_IDENTIFIER = com.koheisuzuk25252525.hitofude.captureuitests; PRODUCT_NAME = "$(TARGET_NAME)"; TEST_TARGET_NAME = Hitofude; TARGETED_DEVICE_FAMILY = "1,2"; SWIFT_VERSION = 5.0; IPHONEOS_DEPLOYMENT_TARGET = 17.0; LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks @loader_path/Frameworks";};};
 F90000000000000000000004 = {isa = XCBuildConfiguration; name = Release; buildSettings = {CODE_SIGNING_ALLOWED = NO; CODE_SIGNING_REQUIRED = NO; GENERATE_INFOPLIST_FILE = YES; PRODUCT_BUNDLE_IDENTIFIER = com.koheisuzuk25252525.hitofude.captureuitests; PRODUCT_NAME = "$(TARGET_NAME)"; TEST_TARGET_NAME = Hitofude; TARGETED_DEVICE_FAMILY = "1,2"; SWIFT_VERSION = 5.0; IPHONEOS_DEPLOYMENT_TARGET = 17.0; LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks @loader_path/Frameworks";};};
 F90000000000000000000005 = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (F90000000000000000000011); runOnlyForDeploymentPostprocessing = 0;};
 F90000000000000000000006 = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;};
 F90000000000000000000007 = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;};
 F90000000000000000000008 = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = ReleaseCaptureUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;};
 F90000000000000000000009 = {isa = PBXGroup; children = (F90000000000000000000010); path = ReleaseCaptureUITests; sourceTree = "<group>";};
 F90000000000000000000010 = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ReleaseCaptureUITests.swift; sourceTree = "<group>";};
 F90000000000000000000011 = {isa = PBXBuildFile; fileRef = F90000000000000000000010;};
'''
edits = [
    ("objects = {", "objects = {" + objects),
    ("targets = (A00000000000000000000002, A00000000000000000000003)", "targets = (A00000000000000000000002, A00000000000000000000003, F90000000000000000000001)"),
    ("children = (A00000000000000000000005, A00000000000000000000006, A00000000000000000000007)", "children = (A00000000000000000000005, A00000000000000000000006, A00000000000000000000007, F90000000000000000000009)"),
    ("children = (A00000000000000000000030, A00000000000000000000031)", "children = (A00000000000000000000030, A00000000000000000000031, F90000000000000000000008)"),
    ("TargetAttributes = {", "TargetAttributes = {F90000000000000000000001 = {CreatedOnToolsVersion = 16.0; TestTargetID = A00000000000000000000002;}; "),
]
updated = original
for old, new in edits:
    if updated.count(old) != 1:
        raise SystemExit("Unexpected project structure: " + old)
    updated = updated.replace(old, new, 1)
project.write_text(updated)

# Copy the existing shared scheme but test only the verification-only UI target.
scheme_path = ROOT / "ios/Hitofude.xcodeproj/xcshareddata/xcschemes"
scheme = ET.parse(scheme_path / "Hitofude.xcscheme")
test_action = scheme.find("TestAction")
test_action.set("buildConfiguration", "Release")
test_action.set("shouldUseLaunchSchemeArgsEnv", "NO")
testables = test_action.find("Testables")
testables.clear()
ref = ET.SubElement(testables, "TestableReference", {"skipped": "NO", "parallelizable": "NO"})
ET.SubElement(ref, "BuildableReference", {
    "BuildableIdentifier": "primary", "BlueprintIdentifier": "F90000000000000000000001",
    "BuildableName": "ReleaseCaptureUITests.xctest", "BlueprintName": "ReleaseCaptureUITests",
    "ReferencedContainer": "container:Hitofude.xcodeproj",
})
scheme.write(scheme_path / "ReleaseCapture.xcscheme", encoding="utf-8", xml_declaration=True)

app_sources = sorted((ROOT / "ios/Hitofude").rglob("*"))
manifest = {
    "application_source_commit": "a04cd41237d4d74b382222aec60ad6c970fda8e2",
    "version": "1.0", "build": "6", "capture_configuration": "Release / iOS Simulator",
    "note": "Real application UI; test-only seeded gameplay, completed through actual UI taps. Not the signed TestFlight binary and not physical-device/ad verification.",
    "fixture": {"mode": "easy", "seed": entry["seed"], "initial_route_cells": prefix_count, "elapsed_seconds_at_launch": 38},
    "application_file_sha256": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in app_sources if p.is_file()},
}
(OUT / "capture-provenance.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
print("Prepared real-puzzle fixture and temporary ReleaseCapture UI-test target; application sources unchanged.")
