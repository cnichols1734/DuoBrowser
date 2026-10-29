# Dynamic Island review companion

This separate, simulator-only ActivityKit app supplies a real synthetic Live Activity. It is not included in DuoBrowser's project, target, bundle or release. It uses no server, push entitlement or personal data. Build products and the generated Xcode project stay under ignored `work/island-lab/`.

With Xcode 27.1 and a deliberately selected, booted test simulator:

```sh
python3 Tests/IslandLab/make_project.py
xcodebuild -project work/island-lab/IslandLab.xcodeproj -scheme IslandLab \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath work/island-lab/DerivedData CODE_SIGNING_ALLOWED=NO build
xcrun simctl install <test-device-id> work/island-lab/DerivedData/Build/Products/Debug-iphonesimulator/IslandLab.app
xcrun simctl launch <test-device-id> dev.local.DuoBrowser.IslandLab --start
```

Return to the Debug DuoBrowser app and enable **Page options → Developer → Show system status**. Full-width mode normally hides the status area, including the compact Live Activity on this runtime; this session-only review switch shows it while retaining the full-width web viewport. The compact activity shows a timer; press and hold it to expand. To end it, open **Island Lab** and tap **End test activity**. The optional `--stop` launch argument also ends all this companion's activities; terminate the companion before relaunching with new arguments. Starting again does not create duplicate activities.

For a repeatable page, run `python3 Tests/native_fixture_server.py` and open `http://127.0.0.1:8765/settling` in DuoBrowser. Scroll with the island compact and expanded, interrupt settling with a new swipe, fold/rotate, edit the synthetic draft and toggle Original Layout. Compare line breaks and reading position before and after. The browser uses iOS reserved-region geometry; the companion does not inject a camera rectangle into production code.

The programmatic native harness separately tests compact/expanded/removed synthetic rectangles, because an actual expanded activity can collapse when a user touches the page. Those assertions verify algorithm behavior and are not proof of the system's actual rectangle reporting or physical-device frame rate.
