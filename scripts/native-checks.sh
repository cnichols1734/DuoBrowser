#!/bin/bash
# Uses only synthetic fixtures. CI creates a disposable simulator; a developer
# can explicitly supply an existing test device with DUO_TEST_DEVICE.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p work/native-ci
derived="${DUO_DERIVED_DATA:-$PWD/DerivedData}"
device="${DUO_TEST_DEVICE:-}"
created=0
http_pid=""
tls_pid=""
cleanup() {
    if [[ -n "$http_pid" ]]; then kill "$http_pid" 2>/dev/null || true; fi
    if [[ -n "$tls_pid" ]]; then kill "$tls_pid" 2>/dev/null || true; fi
    if [[ "$created" == 1 ]]; then
        xcrun simctl shutdown "$device" >/dev/null 2>&1 || true
        xcrun simctl delete "$device" >/dev/null 2>&1 || true
    elif [[ -n "$device" ]]; then
        xcrun simctl terminate "$device" dev.local.DuoBrowser >/dev/null 2>&1 || true
        xcrun simctl launch "$device" dev.local.DuoBrowser >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT
if [[ -z "$device" ]]; then
    runtime=$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; print(next(r["identifier"] for r in json.load(sys.stdin)["runtimes"] if r["isAvailable"] and r["version"] == "27.1" and r["name"].startswith("iOS")))')
    device_type=$(xcrun simctl list devicetypes -j | python3 -c 'import json,sys; print(next(d["identifier"] for d in json.load(sys.stdin)["devicetypes"] if d["name"] == "iPhone Duo"))')
    device=$(xcrun simctl create DuoBrowser-CI "$device_type" "$runtime")
    created=1
    xcrun simctl boot "$device"
fi
xcrun simctl bootstatus "$device" -b
if [[ "${1:-}" != --skip-build ]]; then
    xcodebuild -project DuoBrowser.xcodeproj -scheme DuoBrowser -configuration Debug \
        -destination 'generic/platform=iOS Simulator' -derivedDataPath "$derived" \
        CODE_SIGNING_ALLOWED=NO build > work/native-ci/build.log 2>&1
fi
# Fail if another process occupies our ports; never use an unknown fixture server.
python3 - <<'PY'
import socket
for port in (8765, 8443):
    with socket.socket() as s:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind(('127.0.0.1', port))
PY
openssl req -x509 -newkey rsa:2048 -nodes -keyout work/native-ci/fixture-key.pem \
    -out work/native-ci/fixture-cert.pem -days 1 -subj '/CN=localhost' \
    -addext 'subjectAltName=IP:127.0.0.1' > work/native-ci/certificate.log 2>&1
python3 Tests/native_fixture_server.py > work/native-ci/http.log 2>&1 &
http_pid=$!
python3 Tests/native_fixture_server.py work/native-ci/fixture-cert.pem work/native-ci/fixture-key.pem > work/native-ci/tls.log 2>&1 &
tls_pid=$!
python3 - <<'PY'
import socket,time
for port in (8765,8443):
    for attempt in range(50):
        try:
            with socket.create_connection(('127.0.0.1',port),timeout=0.2): break
        except OSError:
            if attempt == 49: raise
            time.sleep(0.1)
PY
xcrun simctl install "$device" "$derived/Build/Products/Debug-iphonesimulator/DuoBrowser.app"
container=$(xcrun simctl get_app_container "$device" dev.local.DuoBrowser data)
run_receipt() {
    local receipt="$1" minimum="$2"
    shift 2
    xcrun simctl terminate "$device" dev.local.DuoBrowser >/dev/null 2>&1 || true
    # Remove only this Debug harness's synthetic receipt, never browsing files.
    rm -f "$container/Library/Caches/$receipt"
    xcrun simctl launch "$device" dev.local.DuoBrowser --browser-checks "$@"
    python3 - "$container/Library/Caches/$receipt" "$minimum" <<'PY'
import pathlib,sys,time
p=pathlib.Path(sys.argv[1]); minimum=int(sys.argv[2])
for attempt in range(180):
    if p.exists():
        text=p.read_text()
        if 'FAIL:' in text:
            print(text[:16000])  # This harness writes only synthetic fixture results.
            raise SystemExit('Native harness reported a failure: '+p.name)
        passed=sum(line.startswith('PASS:') for line in text.splitlines())
        if passed < minimum: raise SystemExit(f'Incomplete receipt {p.name}: {passed}/{minimum}')
        print(f'{p.name}: {passed} checks passed'); break
    time.sleep(1)
else: raise SystemExit('Timed out waiting for '+p.name)
PY
}
run_receipt NativeBrowserChecks.txt 30
run_receipt CameraSettlingChecks.txt 29 --settling-checks
run_receipt PersistentCookieChecks.txt 1 --persistent-cookie-write
run_receipt PersistentCookieChecks.txt 2 --persistent-cookie-read
run_receipt MemoryChecks.txt 11 --memory-checks
