#!/usr/bin/env python3
"""Exercise the real HTTP gateway and cold replay with a process-level adb double.

No Android SDK, emulator or physical device is used. The double speaks the runner
HTTP contract; Android UI execution itself is covered by the runner's JVM tests.
"""
import base64
import json
import os
from pathlib import Path
import shlex
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request


def request(base, method, path, value=None, empty=False):
    data = b"" if empty else (json.dumps(value).encode() if value is not None else None)
    req = urllib.request.Request(base + path, data=data, method=method,
                                 headers={"Content-Type": "application/json", "Authorization": "Bearer test-token"})
    with urllib.request.urlopen(req, timeout=30) as response:
        return json.load(response)


def fake_adb(args):
    root = Path(os.environ["CUYSCOUT_FAKE_ANDROID"])
    with (root / "commands.jsonl").open("a") as log:
        log.write(json.dumps(args) + "\n")
    if args == ["devices", "-l"]:
        print("List of devices attached\nemulator-5554 device model:Pixel\nUSB_FAKE device model:Demo")
    elif args == ["-list-avds"]:
        print("Pixel")
    elif args[2:5] == ["emu", "avd", "name"]:
        print("Pixel\nOK")
    elif len(args) > 2 and args[2] == "push":
        shutil.copyfile(args[3], root / Path(args[4]).name)
    elif len(args) > 2 and args[2] == "get-state":
        print("device")
    elif len(args) > 3 and args[2] == "shell":
        command = shlex.split(args[3]) if len(args) == 4 else args[3:]
        if command[:2] == ["getprop", "ro.kernel.qemu"]:
            print("0")
        elif command[:2] == ["getprop", "ro.build.version.release"]:
            print("15")
        elif command[:2] == ["dumpsys", "window"]:
            # MIUI deniega que el runner abra la app: el foco queda en el launcher hasta que adb la arranca.
            focus = (root / "foreground").read_text() if (root / "foreground").exists() else "com.miui.home"
            print(f"  mCurrentFocus=Window{{97f65e0 u0 {focus}/.Main}}")
        elif command[:2] == ["am", "start"] or command[:1] == ["monkey"]:
            (root / "foreground").write_text("com.example.wallet")
            print("Starting: Intent")
        elif command[:3] == ["pm", "list", "packages"]:
            print("package:com.example.wallet")
        elif command[:2] == ["pm", "clear"]:
            print("Success")
        elif command[:2] == ["am", "instrument"]:
            config = json.loads((root / Path(command[command.index("cuyscoutConfig") + 1]).name).read_text())
            # The emulator address is translated back to localhost by this host double.
            base = os.environ["CUYSCOUT_FAKE_GATEWAY"]
            session_path = "/session/" + config["sessionId"]
            request(base, "POST", session_path + "/bridge", empty=True)
            while True:
                try:
                    pending = request(base, "GET", session_path + "/bridge/command")
                    if pending:
                        payload = json.loads((root / "tree.json").read_text())
                        request(base, "POST", session_path + "/bridge/result", {
                            "commandID": pending["id"], "success": True,
                            "payloadBase64": base64.b64encode(json.dumps(payload).encode()).decode()})
                    else:
                        time.sleep(.02)
                except urllib.error.HTTPError as error:
                    if error.code == 404:
                        return
                    raise


def run(gateway):
    repo = Path(__file__).resolve().parent.parent
    with tempfile.TemporaryDirectory(prefix="cuyscout-android-http-") as directory:
        root = Path(directory)
        for relative in ["sdk/platform-tools/adb", "sdk/emulator/emulator"]:
            tool = root / relative
            tool.parent.mkdir(parents=True, exist_ok=True)
            tool.write_text("#!/bin/sh\nexec " + shlex.quote(sys.executable) + " " + shlex.quote(str(Path(__file__).resolve())) + " --fake-adb \"$@\"\n")
            tool.chmod(0o755)
        (root / "host.apk").touch(); (root / "test.apk").touch(); (root / "wallet.apk").touch()
        shutil.copyfile(repo / "Tests/CuyScoutCoreTests/Fixtures/android/runner-tree.json", root / "tree.json")
        with socket.socket() as reserved:
            reserved.bind(("127.0.0.1", 0)); port = reserved.getsockname()[1]
        base = f"http://127.0.0.1:{port}"
        env = dict(os.environ, ANDROID_HOME=str(root / "sdk"), CUYSCOUT_ARTIFACT_DIR=str(root / "artifacts"),
                   CUYSCOUT_FAKE_ANDROID=str(root), CUYSCOUT_FAKE_GATEWAY=base, CUYSCOUT_TOKEN="test-token",
                   CUYSCOUT_CONFIG=str(root / "absent.yaml"), CUYSCOUT_AUTORECORD="true",
                   CUYSCOUT_ANDROID_HOST_APK=str(root / "host.apk"), CUYSCOUT_ANDROID_TEST_APK=str(root / "test.apk"),
                   CUYSCOUT_BIND_ADDRESS="127.0.0.1", CUYSCOUT_URL=base)
        env.pop("CUYSCOUT_DEVICE_GATEWAY_URL", None)
        with (root / "gateway.log").open("w") as log:
            process = subprocess.Popen([str(Path(gateway).resolve()), str(port)], env=env, stdout=log, stderr=log)
            try:
                for _ in range(100):
                    try:
                        request(base, "GET", "/status"); break
                    except (OSError, urllib.error.URLError):
                        if process.poll() is not None: raise RuntimeError((root / "gateway.log").read_text())
                        time.sleep(.1)
                else:
                    raise AssertionError("Gateway did not start")
                for serial, driver in [("emulator-5554", "android-emulator"), ("USB_FAKE", "android-device")]:
                    caps = {"appium:platformName": "Android", "appium:udid": serial,
                            "appium:appPackage": "com.example.wallet", "appium:appActivity": ".LoginActivity",
                            "appium:app": str(root / "wallet.apk"), "appium:xcodeOrgId": "ignored-test-value"}
                    (root / "foreground").write_text("com.miui.home")
                    created = request(base, "POST", "/session", {"capabilities": {"alwaysMatch": caps}})["value"]
                    sid = created["sessionId"]; path = "/session/" + sid
                    expected_launch = "'am' 'start' '-W' '--user' '0' '-n' 'com.example.wallet/com.example.wallet.LoginActivity'"
                    for _ in range(100):  # el gateway la arranca en segundo plano cuando el runner ya atiende
                        launched = [json.loads(line) for line in (root / "commands.jsonl").read_text().splitlines()]
                        if any(args[-1:] == [expected_launch] for args in launched): break
                        time.sleep(.1)
                    else:
                        raise AssertionError(f"{driver}: el gateway no trajo la app al frente por adb cuando el foco quedó en el launcher")
                    assert created["capabilities"]["appium:driverId"] == driver
                    assert created["capabilities"]["cuyscout:capabilityWarnings"] == ["Ignored appium:xcodeOrgId on Android"]
                    fetched = request(base, "GET", path)["value"]["capabilities"]
                    assert fetched["platformName"] == "Android" and fetched["appium:appActivity"] == ".LoginActivity"
                    for _ in range(100):
                        if request(base, "GET", path + "/bridge/status")["runnerAttached"]: break
                        time.sleep(.05)
                    else: raise AssertionError("Fake runner did not attach")
                    readiness = request(base, "GET", path + "/readiness?ui=false")["value"]
                    assert readiness["bridgeConnected"] == readiness["xctestBridgeConnected"] is True
                    observation = request(base, "GET", path + "/observe")["value"]
                    assert "Demo Wallet" in observation["texts"] and observation["actions"]
                    request(base, "POST", path + "/actions", {"type": "assertVisible", "selector": {"strategy": "accessibilityIdentifier", "value": "login"}})
                    typescript = urllib.request.Request(base + path + "/recording/appium/typescript", headers={"Authorization": "Bearer test-token"})
                    with urllib.request.urlopen(typescript, timeout=10) as response:
                        exported = response.read().decode()
                    assert "platformName: 'Android'" in exported and "'appium:appPackage'" in exported
                    assert "wdaLaunchTimeout" not in exported and ".LoginActivity" in exported
                    stopped = request(base, "POST", path + "/recording/stop", {})
                    assert "platformName: 'Android'" in stopped["generatedAppiumTypeScript"]
                    with urllib.request.urlopen(typescript, timeout=10) as response:
                        assert "platformName: 'Android'" in response.read().decode()
                    request(base, "DELETE", path)
                    artifact = root / "artifacts" / (sid + ".json")
                    original = artifact.read_bytes()
                    assert "platformName: 'Android'" in json.loads(original)["recording"]["generatedAppiumTypeScript"]
                    cli = subprocess.run([str(Path(gateway).resolve()), "export-appium", str(artifact), "ts"], env=env, capture_output=True, text=True, check=True)
                    assert "platformName: 'Android'" in cli.stdout and "wdaLaunchTimeout" not in cli.stdout
                    maestro = subprocess.run([str(Path(gateway).resolve()), "export-maestro", str(artifact)], env=env, capture_output=True, text=True, check=True)
                    assert 'appId: "com.example.wallet"' in maestro.stdout
                    for mode in ["preserve", "restart", "reinstall"]:
                        offset = len((root / "commands.jsonl").read_text().splitlines())
                        preflight = request(base, "POST", f"/artifacts/{sid}/replay/preflight", {"preparation": mode})
                        assert preflight["ready"], preflight
                        result = request(base, "POST", f"/artifacts/{sid}/replay", {"preparation": mode})
                        assert result["success"] and result["executedSteps"] >= 1, result
                        commands = [json.loads(line) for line in (root / "commands.jsonl").read_text().splitlines()[offset:]]
                        stop = any(args[-1] == "'am' 'force-stop' '--user' '0' 'com.example.wallet'" for args in commands)
                        clear = any(args[-1] == "'pm' 'clear' '--user' '0' 'com.example.wallet'" for args in commands)
                        assert stop == (mode != "preserve") and clear == (mode == "reinstall"), commands
                        assert artifact.read_bytes() == original, "Cold replay rewrote its source artifact"
                    from test_android_project import exercise_project
                    exercise_project(gateway, request, base, env, root, serial, driver)
                    print(f"PASS {driver}: HTTP session, capabilities, readiness, observe, recording, preserve/restart/reinstall")
            finally:
                process.terminate()
                try: process.wait(timeout=10)
                except subprocess.TimeoutExpired: process.kill(); process.wait()


if __name__ == "__main__":
    if sys.argv[1:2] == ["--fake-adb"]:
        fake_adb(sys.argv[2:])
    else:
        run(sys.argv[1] if len(sys.argv) > 1 else ".build/debug/cuyscout")
