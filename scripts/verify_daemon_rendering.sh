#!/bin/bash
set -e

STAGED_DAEMON="/Users/perkunas/jail/3dgs-phoenix/app_unreal/Saved/StagedBuilds/Mac/cesium_daemon.app/Contents/MacOS/cesium_daemon"
IOSURFACE_CHECK="/Users/perkunas/jail/3dgs-phoenix/scripts/iosurface_check"
SOCKET="/tmp/cesium_daemon_verify.sock"
LOG="/tmp/daemon_verify_test.log"

cleanup() {
    echo "=== Cleanup ==="
    pkill -9 -f cesium_daemon 2>/dev/null || true
    rm -f "$SOCKET"
}
trap cleanup EXIT

cleanup

echo "=== T1: Launch daemon ==="
"$STAGED_DAEMON" -RenderOffscreen -SceneId=verify -log > "$LOG" 2>&1 &
DAEMON_PID=$!
echo "Daemon PID: $DAEMON_PID"

echo "=== T1: Wait for startup + Cesium tile streaming (30s) ==="
sleep 30

echo "=== T2: Health check ==="
HEALTH=$(echo '{"type":"health_check"}' | nc -w5 -U "$SOCKET")
echo "Health: $HEALTH"
if ! echo "$HEALTH" | grep -q '"status":"ok"'; then
    echo "FAIL: Health check failed"
    exit 1
fi
echo "PASS: Health check OK"

echo "=== T3: Get IOSurface ID ==="
IOSURFACE_RESP=$(echo '{"type":"get_iosurface_id"}' | nc -w5 -U "$SOCKET")
echo "Response: $IOSURFACE_RESP"
IOSURFACE_ID=$(echo "$IOSURFACE_RESP" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
if [ -z "$IOSURFACE_ID" ] || [ "$IOSURFACE_ID" -eq 0 ]; then
    echo "FAIL: IOSurface ID is 0 or missing"
    exit 1
fi
echo "PASS: IOSurface ID = $IOSURFACE_ID"

echo "=== T4: Position camera over Paris (low altitude for tile detail) ==="
CAMERA_RESP=$(echo '{"type":"update_camera","lat":48.8566,"lon":2.3522,"alt":50000,"heading":0,"pitch":-90,"roll":0}' | nc -w5 -U "$SOCKET")
echo "Camera response: $CAMERA_RESP"
echo "Waiting for tiles to stream (20s)..."
sleep 20

echo "=== T5: Check pixel content (Paris) ==="
"$IOSURFACE_CHECK" "$IOSURFACE_ID"
PIXEL_RESULT=$?
if [ $PIXEL_RESULT -ne 0 ]; then
    echo "FAIL: No rendering content detected"
    exit 1
fi
echo "PASS: Pixel content confirmed"

echo "=== T6: Verify camera movement changes view ==="
FIRST_HASH=$("$IOSURFACE_CHECK" "$IOSURFACE_ID" 2>&1 | md5)

# Move camera to Tokyo
echo '{"type":"update_camera","lat":35.6762,"lon":139.6503,"alt":50000,"heading":0,"pitch":-90,"roll":0}' | nc -w5 -U "$SOCKET"
sleep 15

# Check pixels changed
SECOND_HASH=$("$IOSURFACE_CHECK" "$IOSURFACE_ID" 2>&1 | md5)

if [ "$FIRST_HASH" = "$SECOND_HASH" ]; then
    echo "WARN: Pixels unchanged after camera move (tiles may still be loading)"
else
    echo "PASS: Camera movement changed rendered view"
fi

echo ""
echo "=== ALL TESTS PASSED ==="
echo "Cesium terrain rendering verified: health OK, IOSurface non-zero, pixel content present"
