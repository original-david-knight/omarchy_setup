"""Exercise the Litra command boundary with synthetic HID traffic, without USB."""
import errno
import fcntl
import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
HELPER = Path(__file__).resolve().parents[1] / "omarchy/.config/omarchy/plugins/david.meeting/litra"
loader = importlib.machinery.SourceFileLoader("meeting_litra", str(HELPER))
spec = importlib.util.spec_from_loader(loader.name, loader)
litra = importlib.util.module_from_spec(spec)
loader.exec_module(litra)


class FakeLight:
    """A device emulator with an independent packet contract and mutable settings."""
    def __init__(self):
        self.power = False
        self.brightness = 120
        self.temperature = 4000
        self.pending = []
        self.ignore_write = False
        self.replacement = None
        self.write_error = None
        self.closed = False

    def close(self):
        self.closed = True

    def write(self, data):
        if self.write_error:
            raise self.write_error
        if len(data) != 20 or data[:3] != bytes.fromhex("11ff04"):
            raise AssertionError(f"Invalid outgoing packet: {data.hex()}")
        opcode = data[3]
        if opcode in (0x1C, 0x4C, 0x9C):
            width = 1 if opcode == 0x1C else 2
            if any(data[4 + width:]):
                raise AssertionError("Setting report padding must be zero")
            value = int.from_bytes(data[4:4 + width], "big")
            if not self.ignore_write:
                if opcode == 0x1C:
                    self.power = bool(value)
                elif opcode == 0x4C:
                    self.brightness = value
                else:
                    self.temperature = value
            self.pending.append(data)
            return
        if any(data[4:]):
            raise AssertionError("Query report payload must be zero")
        if self.replacement is not None:
            self.pending.extend(self.replacement)
        elif opcode == 0x01:
            self.pending.append(bytes.fromhex("11ff0401") + bytes((int(self.power),)) + bytes(15))
        elif opcode == 0x31:
            self.pending.append(bytes.fromhex("11ff0431") + self.brightness.to_bytes(2, "big") + bytes(14))
        elif opcode == 0x81:
            self.pending.append(bytes.fromhex("11ff0481") + self.temperature.to_bytes(2, "big") + bytes(14))
        else:
            raise AssertionError(f"Unsupported query: {opcode}")

    def read(self, timeout):
        if timeout <= 0:
            raise AssertionError("Reads must have a positive deadline")
        return self.pending.pop(0) if self.pending else None


class CommandTests(unittest.TestCase):
    def setUp(self):
        self.runtime = tempfile.TemporaryDirectory()
        self.addCleanup(self.runtime.cleanup)
        self.environment = patch.dict(os.environ, {"XDG_RUNTIME_DIR": self.runtime.name})
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.device = FakeLight()

    def run_command(self, args, *, factory=None):
        output = io.StringIO()
        with patch.object(litra, "find_device", return_value=Path("/dev/hidraw7")), \
                patch.object(litra, "Device", factory or (lambda path: self.device)), \
                patch("sys.stdout", output):
            code = litra.main(args)
        return code, json.loads(output.getvalue())

    def test_status_reads_all_fields_and_observes_physical_changes(self):
        self.assertEqual(self.run_command(["status"]), (0, {
            "status": "ready", "power": False, "brightness": 120, "temperature": 4000,
        }))
        self.device.power = True
        self.device.brightness = 250
        self.device.temperature = 6500
        self.assertEqual(self.run_command(["status"]), (0, {
            "status": "ready", "power": True, "brightness": 250, "temperature": 6500,
        }))
        self.assertTrue(self.device.closed)

    def test_absolute_writes_return_observed_state_and_can_be_repeated(self):
        for args, expected in [
            (["set", "power", "on"], {"status": "ready", "power": True, "brightness": 120, "temperature": 4000}),
            (["set", "brightness", "20"], {"status": "ready", "power": True, "brightness": 20, "temperature": 4000}),
            (["set", "temperature", "2700"], {"status": "ready", "power": True, "brightness": 20, "temperature": 2700}),
            (["set", "power", "off"], {"status": "ready", "power": False, "brightness": 20, "temperature": 2700}),
        ]:
            with self.subTest(args=args):
                self.assertEqual(self.run_command(args), (0, expected))
                self.assertEqual(self.run_command(args), (0, expected))

    def test_write_without_matching_readback_never_reports_success(self):
        self.device.ignore_write = True
        self.assertEqual(self.run_command(["set", "brightness", "200"]), (1, {
            "status": "protocol", "message": "Litra Glow did not confirm the requested setting.",
        }))

    def test_timeout_after_write_does_not_invent_a_state(self):
        self.device.replacement = []
        self.assertEqual(self.run_command(["set", "power", "on"]), (1, {
            "status": "protocol", "message": "Litra Glow did not answer the power query.",
        }))

    def test_write_failure_never_reports_success(self):
        self.device.write_error = OSError(errno.EIO, "synthetic failure")
        self.assertEqual(self.run_command(["set", "power", "on"]), (1, {
            "status": "error", "message": "Litra Glow could not be reached. Reconnect the light and try again.",
        }))

    def test_only_matching_complete_valid_responses_become_state(self):
        cases = [
            ([], "Litra Glow did not answer the power query."),
            ([bytes.fromhex("11ff0401")], "Litra Glow returned an incomplete or unsupported report."),
            ([bytes.fromhex("11ff040102") + bytes(15)], "Litra Glow returned an invalid power value."),
            ([bytes.fromhex("11fe040101") + bytes(15)], "Litra Glow did not answer the power query."),
            ([bytes.fromhex("11ff04310078") + bytes(14)], "Litra Glow did not answer the power query."),
            ([bytes.fromhex("11ffff040102") + bytes(14)], "Litra Glow rejected the command."),
        ]
        for frames, message in cases:
            with self.subTest(message=message, frames=frames):
                self.device = FakeLight()
                self.device.replacement = frames
                self.assertEqual(self.run_command(["status"]), (1, {"status": "protocol", "message": message}))

    def test_invalid_brightness_or_temperature_drops_partial_snapshot(self):
        for key, value in (("brightness", 251), ("temperature", 2750)):
            with self.subTest(key=key):
                self.device = FakeLight()
                setattr(self.device, key, value)
                self.assertEqual(self.run_command(["status"]), (1, {
                    "status": "protocol", "message": f"Litra Glow returned an invalid {key} value.",
                }))

    def test_permission_failure_is_actionable_and_contains_no_state(self):
        def denied(path):
            raise PermissionError(errno.EACCES, "synthetic device details")
        self.assertEqual(self.run_command(["status"], factory=denied), (1, {
            "status": "permission", "message": "Litra Glow access is denied. Run the meeting widget installer and reconnect the light.",
        }))

    def test_disconnection_during_transaction_is_missing(self):
        self.device.write_error = OSError(errno.ENODEV, "synthetic disconnection")
        self.assertEqual(self.run_command(["status"]), (1, {
            "status": "missing", "message": "Litra Glow disconnected.",
        }))

    def test_busy_transaction_exits_and_next_request_recovers(self):
        lock = Path(self.runtime.name) / "david-meeting-litra-hidraw7.lock"
        with lock.open("w") as held:
            fcntl.flock(held, fcntl.LOCK_EX)
            with patch.object(litra, "LOCK_TIMEOUT", 0):
                self.assertEqual(self.run_command(["status"]), (1, {
                    "status": "busy", "message": "Litra Glow is busy. Try again.",
                }))
        self.assertEqual(self.run_command(["status"]), (0, {
            "status": "ready", "power": False, "brightness": 120, "temperature": 4000,
        }))

    def test_cli_rejects_invalid_values_before_touching_usb(self):
        for args in (["set", "power", "true"], ["set", "brightness", "19"],
                     ["set", "brightness", "251"], ["set", "temperature", "2750"],
                     ["set", "temperature", "6501"], ["set", "brightness", "word"], []):
            with self.subTest(args=args):
                code, result = self.run_command(args, factory=lambda path: self.fail("USB opened for invalid arguments"))
                self.assertEqual(code, 1)
                self.assertEqual(result["status"], "error")

    def test_short_hid_write_is_a_failed_command(self):
        device = litra.Device.__new__(litra.Device)
        device.fd = -1
        with patch.object(litra.os, "write", return_value=4):
            with self.assertRaisesRegex(litra.LightError, "complete command"):
                litra.transact(device, ("power", 1))


class DiscoveryTests(unittest.TestCase):
    def test_discovers_only_glow_with_vendor_usage(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name, identity, descriptor in [
                ("hidraw0", "0003:0000046D:0000C901", bytes.fromhex("0643ff")),
                ("hidraw1", "0003:0000046D:0000C900", bytes.fromhex("05010900")),
                ("hidraw2", "0003:0000046D:0000C900", bytes.fromhex("0643ff0a0202a101")),
            ]:
                device = root / name / "device"
                device.mkdir(parents=True)
                (device / "uevent").write_text(f"HID_ID={identity}\n")
                (device / "report_descriptor").write_bytes(descriptor)
            self.assertEqual(litra.find_device(root), Path("/dev/hidraw2"))
            (root / "hidraw2/device/report_descriptor").write_bytes(bytes.fromhex("0501"))
            original_find = litra.find_device
            with patch.object(litra, "find_device", side_effect=lambda: original_find(root)), patch("sys.stdout", new_callable=io.StringIO) as output:
                self.assertEqual(litra.main(["status"]), 1)
                self.assertEqual(json.loads(output.getvalue()), {
                    "status": "missing", "message": "Litra Glow is not connected.",
                })

    def test_embedded_usage_bytes_do_not_select_unrelated_interface(self):
        self.assertTrue(litra.vendor_usage(bytes.fromhex("0643ff")))
        self.assertFalse(litra.vendor_usage(bytes.fromhex("270643ff00")))
        self.assertFalse(litra.vendor_usage(bytes.fromhex("0643")))


if __name__ == "__main__":
    unittest.main()
