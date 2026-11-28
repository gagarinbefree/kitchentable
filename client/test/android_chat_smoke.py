"""Verify messaging between two Android installations already paired by QR."""
import argparse
import os
import re
import subprocess
import time
import uuid
from xml.etree import ElementTree

PACKAGE = os.environ.get("KITCHENTABLE_ANDROID_PACKAGE", "com.example.kitchentable")
ADB = os.environ.get("ADB", "adb")


def shell(device, *args):
    return subprocess.run([ADB, "-s", device, "shell", *args], capture_output=True,
                          text=True, encoding="utf-8", errors="replace", timeout=45, check=True).stdout


def label(node):
    return node.get("text", "") + "\n" + node.get("content-desc", "")


def tap(device, node):
    x1, y1, x2, y2 = map(int, re.findall(r"\d+", node.attrib["bounds"]))
    shell(device, "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))


def wait_for(device, predicate, description):
    deadline = time.monotonic() + 150
    foreground = set()
    while time.monotonic() < deadline:
        try:
            dump = shell(device, ": > /data/local/tmp/kt-screen.xml && "
                                 "uiautomator dump /data/local/tmp/kt-screen.xml >/dev/null && "
                                 "cat /data/local/tmp/kt-screen.xml")
            start = dump.find("<?xml")
            if start < 0:
                continue
            nodes = list(ElementTree.fromstring(dump[start:]).iter("node"))
        except (subprocess.TimeoutExpired, subprocess.CalledProcessError, ElementTree.ParseError):
            time.sleep(1)
            continue
        foreground = {n.get("package") for n in nodes}
        for node in nodes:
            if node.get("resource-id") == "android:id/alertTitle" and "responding" in label(node):
                raise RuntimeError(f"{device}: {label(node).strip()}")
        for node in nodes:
            if node.get("package") == PACKAGE and predicate(node):
                return node
        time.sleep(.6)
    raise TimeoutError(f"{device}: {description}; foreground packages {foreground}")


def displayed(device, text):
    return wait_for(device, lambda n: text in label(n), text)


def foreground(device, user):
    shell(device, "am", "start", "-W", "--user", user, "-a", "android.intent.action.MAIN", "-c",
          "android.intent.category.LAUNCHER", "-f", "0x10200000", "-n", f"{PACKAGE}/com.example.kitchentable.MainActivity")
    if user != "current":
        wait_for_profile(device, user)


def wait_for_profile(device, user):
    expected = re.compile(r"mCurrentFocus=Window\{\S+ u" + re.escape(user) + r" " + re.escape(PACKAGE) + r"/")
    deadline = time.monotonic() + 60
    while time.monotonic() < deadline:
        if expected.search(shell(device, "dumpsys", "window")):
            return
        time.sleep(.3)
    raise TimeoutError(f"Android did not bring profile {user} to the foreground")


def stop(device, user):
    shell(device, "am", "force-stop", "--user", user, PACKAGE)


def launch(device, user, cold=False, other_number=None):
    shell(device, "input", "keyevent", "KEYCODE_WAKEUP")
    shell(device, "wm", "dismiss-keyguard")
    if cold:
        stop(device, user)
    foreground(device, user)
    displayed(device, "На связи")
    def own_number(node):
        match = re.search(r"Мой номер:\s*(\d+)", label(node))
        return match.group(1) if match else None

    node = wait_for(device, lambda n: own_number(n) not in (None, other_number),
                    f"subscriber number for profile {user}")
    return own_number(node)


def enter(device, hint, text):
    field = wait_for(device, lambda n: n.get("class") == "android.widget.EditText"
                     and n.get("enabled") == "true", hint)
    tap(device, field)
    editable = lambda n: n.get("class") == "android.widget.EditText" and n.get("focused") == "true"
    current = wait_for(device, editable, "focused field").get("text", "")
    for _ in range(4):
        if current == text:
            return
        if text.startswith(current):
            shell(device, "input", "text", text[len(current):])
        else:
            shell(device, "input", "keycombination", "113", "29")
            shell(device, "input", "keyevent", "KEYCODE_DEL")
            shell(device, "input", "text", text)
        current = wait_for(device, editable, "entered text").get("text", "")
    if current != text:
        raise AssertionError(f"Could not enter {hint} on {device}")


def click(device, text):
    tap(device, wait_for(device, lambda n: text in label(n) and n.get("enabled") == "true", text))


def open_existing(device, peer):
    edit_label = f"Редактировать имя абонента {peer}"
    row = wait_for(device, lambda n: n.get("clickable") == "true" and
                   any(label(child).strip() == edit_label for child in n.findall("node")),
                   f"conversation with subscriber {peer}")
    tap(device, row)
    wait_for(device, lambda n: n.get("class") == "android.widget.EditText", "message composer")


def send(device, text):
    enter(device, "Сообщение", text)
    click(device, "Отправить")
    wait_for(device, lambda n: n.get("class") != "android.widget.EditText" and text in label(n), text)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("first")
    parser.add_argument("second", nargs="?", help="ADB serial of the second Android device")
    parser.add_argument("--peer-user", help="Android profile ID of the second installation on the first device")
    parser.add_argument("--expect", help="Verify a previously sent private message after cold launch")
    args = parser.parse_args()
    if bool(args.second) == bool(args.peer_user):
        parser.error("Specify either a second device or --peer-user PROFILE_ID")
    if args.second == args.first:
        parser.error("Use --peer-user for two installations on one device")
    a, b = args.first, args.second or args.first
    owner = shell(a, "am", "get-current-user").strip()
    peer_user = args.peer_user or "current"
    if args.peer_user and (not peer_user.isdecimal() or peer_user == owner):
        parser.error("Choose a separate numeric Android profile ID")

    def show(device, user):
        if args.peer_user:
            foreground(device, user)

    for device, user in ((a, owner), (b, peer_user)):
        if int(shell(device, "getprop", "ro.build.version.sdk")) >= 33:
            shell(device, "pm", "grant", "--user", user, PACKAGE, "android.permission.POST_NOTIFICATIONS")

    alice = launch(a, owner, cold=True)
    bob = launch(b, peer_user, cold=True, other_number=alice)
    if alice == bob:
        raise AssertionError("The two installations must be separate subscriber accounts")
    print(f"Subscribers: {alice}, {bob}", flush=True)
    if args.expect:
        for device, user, peer in ((a, owner, bob), (b, peer_user, alice)):
            show(device, user)
            open_existing(device, peer)
            displayed(device, args.expect)
        print("Saved personal message present on both cold-started clients.", flush=True)
    else:
        tag = uuid.uuid4().hex[:7]
        first, reply, missed = (f"KT-{tag}-{word}" for word in ("hello", "reply", "back"))
        show(a, owner)
        open_existing(a, bob)
        send(a, first)
        show(b, peer_user)
        displayed(b, first)
        open_existing(b, alice)
        displayed(b, first)
        print("Private delivery: OK", flush=True)
        send(b, reply)
        show(a, owner)
        displayed(a, reply)
        print("Private reply: OK", flush=True)
        stop(b, peer_user)
        send(a, missed)
        if launch(b, peer_user) != bob:
            raise AssertionError("Subscriber number changed after relaunch")
        open_existing(b, alice)
        displayed(b, missed)
        print(f"Catch-up: OK. Persistence marker: {missed}", flush=True)
