"""Offline checks for the Arctis Nova Pro Omni helper: frame parsing, encoding, and device discovery."""
import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

# The helper has no .py suffix; keep its bytecode cache out of the stowed plugin folder.
sys.dont_write_bytecode = True
PLUGIN = Path(__file__).resolve().parents[1] / "omarchy/.config/omarchy/plugins/david.headset"
loader = importlib.machinery.SourceFileLoader("headset", str(PLUGIN / "headset"))
spec = importlib.util.spec_from_loader(loader.name, loader)
headset = importlib.util.module_from_spec(spec)
loader.exec_module(headset)

# A real `01 b0` reply captured from the DAC: 28% battery, spare 100%, discharging,
# link connected, ANC on at low strength, transparency 8, mic muted, LED 10, 30 min auto-off.
STATUS_REPLY = bytes.fromhex("01b0000004011c640801020a050008080100") + bytes(46)

# Omni/Elite radio model layout documented by Cisien/arctis-things. Ten
# peak filters at Q=1.41; only the 125 Hz band is boosted (+2 dB = 0x14).
EQ_PLUS_2_AT_125 = (
    b"\x01\x1b\x04Custom" + b"Custom" + bytes(55)
    + bytes.fromhex("200001008205 400001008205 7d0001148205 fa0001008205 f40101008205 "
                    "e80301008205 d00701008205 a00f01008205 401f01008205 803e01008205")
    + bytes(906)
)


class FakeDevice:
    """Stands in for the hidraw node: records writes and replays queued frames."""

    def __init__(self, replies=()):
        self.path = "/dev/hidraw-fake"
        self.fd = -1
        self.written = []
        self.features = []
        self.replies = list(replies)

    def write(self, data):
        self.written.append(bytes(data))
        if data[1] == 0xB0:
            self.replies.append(STATUS_REPLY)

    def read(self, timeout):
        return self.replies.pop(0) if self.replies else None

    def write_feature(self, data):
        self.features.append(bytes(data))

    def drain(self, state, seconds=0.05):
        changed = {}
        while self.replies:
            changed.update(headset.parse_event(self.replies.pop(0), state))
        return changed

    def query_status(self, state):
        return headset.Device.query_status(self, state)

    def close(self):
        pass


class ParsingTests(unittest.TestCase):
    def test_status_reply_decodes_every_field_the_panel_shows(self):
        status = headset.parse_status(STATUS_REPLY)
        self.assertEqual(status["battery"], 28)
        self.assertEqual(status["spare_battery"], 100)
        self.assertEqual(status["charging"], "discharging")
        self.assertEqual(status["link"], "connected")
        self.assertTrue(status["online"])
        self.assertEqual(status["anc"], "on")
        self.assertEqual(status["anc_level"], 1)
        self.assertEqual(status["transparency"], 8)
        self.assertTrue(status["mic_muted"])
        self.assertEqual(status["mic_led"], 10)
        self.assertEqual(status["auto_off_minutes"], 30)
        self.assertEqual(status["wireless_mode"], "speed")

    def test_other_frames_are_not_mistaken_for_status(self):
        self.assertIsNone(headset.parse_status(bytes.fromhex("0725190000") + bytes(59)))
        self.assertIsNone(headset.parse_status(b"\x01\xb0"))

    def test_volume_knob_events_map_to_percent_with_zero_loudest(self):
        state = {}
        changed = headset.parse_event(bytes.fromhex("072519") + bytes(61), state)
        self.assertEqual(changed, {"volume_raw": 25, "volume": 55})
        self.assertEqual(headset.volume_percent(0), 100)
        self.assertEqual(headset.volume_percent(56), 0)
        self.assertEqual(headset.volume_raw(100), 0)
        self.assertEqual(headset.volume_raw(0), 56)
        for percent in range(0, 101):
            self.assertLessEqual(abs(headset.volume_percent(headset.volume_raw(percent)) - percent), 1)

    def test_push_events_update_anc_mic_battery_and_eq_bands(self):
        state = {"eq_bands": None}
        headset.parse_event(bytes.fromhex("07bd01") + bytes(61), state)
        headset.parse_event(bytes.fromhex("07b803") + bytes(61), state)
        headset.parse_event(bytes.fromhex("07bb00") + bytes(61), state)
        headset.parse_event(bytes.fromhex("07b7405f02") + bytes(59), state)
        headset.parse_event(bytes.fromhex("07310318") + bytes(60), state)
        headset.parse_event(bytes.fromhex("07b5010108") + bytes(59), state)
        self.assertEqual(state["anc"], "transparent")
        self.assertEqual(state["anc_level"], 3)
        self.assertFalse(state["mic_muted"])
        self.assertEqual((state["battery"], state["spare_battery"], state["charging"]), (64, 95, "charging"))
        self.assertEqual(state["eq_bands"][2], 24)
        self.assertEqual(len(state["eq_bands"]), 10)
        self.assertTrue(state["online"])

    def test_unknown_events_change_nothing(self):
        state = {"anc": "on"}
        self.assertEqual(headset.parse_event(bytes.fromhex("071900") + bytes(61), state), {})
        self.assertEqual(state, {"anc": "on"})


class EncodingTests(unittest.TestCase):
    def frame(self, *payload):
        return bytes(payload) + bytes(64 - len(payload))

    def test_settings_encode_to_the_documented_opcodes(self):
        self.assertEqual(headset.encode("anc", "on"), [self.frame(0x01, 0xBD, 0x02)])
        self.assertEqual(headset.encode("anc", "transparent"), [self.frame(0x01, 0xBD, 0x01)])
        self.assertEqual(headset.encode("anc-level", "high"), [self.frame(0x01, 0xB8, 0x03)])
        self.assertEqual(headset.encode("anc-level", "2"), [self.frame(0x01, 0xB8, 0x02)])
        self.assertEqual(headset.encode("transparency", "7"), [self.frame(0x01, 0xB9, 0x07)])
        self.assertEqual(headset.encode("volume", "55"), [self.frame(0x01, 0x25, 25)])
        self.assertEqual(headset.encode("limiter", "on"), [self.frame(0x01, 0x27, 0x01)])

    def test_eq_is_a_full_custom_radio_model(self):
        self.assertEqual(headset.encode("eq-band", "3:24"), [EQ_PLUS_2_AT_125])
        self.assertEqual(len(EQ_PLUS_2_AT_125), 1036)

    def test_eq_gains_are_signed_tenths_of_a_decibel(self):
        bands = [0, 40, 19, 21] + [20] * 6
        report = headset.encode_eq(bands)
        gains = [struct.unpack_from("<HBbH", report, 70 + i * 6)[2] for i in range(10)]
        self.assertEqual(gains, [-100, 100, -5, 5, 0, 0, 0, 0, 0, 0])

    def test_flat_replaces_all_gains_in_one_feature_report(self):
        reports = headset.encode("eq-flat", "1", [0, 40] * 5)
        self.assertEqual(len(reports), 1)
        gains = [struct.unpack_from("<HBbH", reports[0], 70 + i * 6)[2] for i in range(10)]
        self.assertEqual(gains, [0] * 10)

    def test_sidetone_keeps_the_level_byte_at_least_one_when_off(self):
        self.assertEqual(headset.encode("sidetone", "0"), [self.frame(0x01, 0x38, 0x00, 0x01)])
        self.assertEqual(headset.encode("sidetone", "6"), [self.frame(0x01, 0x38, 0x01, 0x06)])

    def test_bad_values_are_rejected_before_anything_is_written(self):
        for key, value in (("anc", "loud"), ("anc-level", "9"), ("transparency", "0"),
                           ("volume", "101"), ("sidetone", "11"), ("eq-band", "11:20"), ("eq-band", "2:41"),
                           ("eq-band", "2"), ("bogus", "1")):
            with self.assertRaises(headset.HeadsetError, msg=f"{key}={value}"):
                headset.encode(key, value)


class DiscoveryTests(unittest.TestCase):
    def make_node(self, root, name, hid_id, descriptor):
        device = root / name / "device"
        device.mkdir(parents=True)
        (device / "uevent").write_text(f"DRIVER=hid-generic\nHID_ID={hid_id}\nHID_NAME=SteelSeries Arctis Nova Pro Omni\n")
        (device / "report_descriptor").write_bytes(descriptor)

    def test_picks_the_vendor_interface_of_the_omni_only(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.make_node(root, "hidraw3", "0003:00001038:00002290", bytes.fromhex("050c0901a101"))  # consumer keys
            self.make_node(root, "hidraw4", "0003:0000046D:0000C52B", bytes.fromhex("06c0ff0a0100"))  # another vendor
            self.make_node(root, "hidraw5", "0003:00001038:00002290", bytes.fromhex("06c0ff0a0100a101"))
            with patch.dict(os.environ, {"DAVID_HEADSET_SYSFS": folder, "DAVID_HEADSET_DEV": "/dev"}):
                self.assertEqual(headset.find_device(), "/dev/hidraw5")

    def test_reports_absence_without_a_device(self):
        with tempfile.TemporaryDirectory() as folder:
            with patch.dict(os.environ, {"DAVID_HEADSET_SYSFS": folder, "XDG_STATE_HOME": folder}):
                result = subprocess.run([str(PLUGIN / "headset"), "status"], text=True, capture_output=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        status = json.loads(result.stdout)
        self.assertFalse(status["connected"])
        self.assertIn("not connected", status["error"])


class CommandTests(unittest.TestCase):
    def test_apply_refreshes_status_for_reported_keys_and_remembers_the_rest(self):
        with tempfile.TemporaryDirectory() as folder:
            with patch.dict(os.environ, {"XDG_STATE_HOME": folder}):
                device = FakeDevice()
                state = headset.fresh_state()
                headset.apply(device, state, "anc", "transparent")
                self.assertEqual(device.written[0][:3], bytes([0x01, 0xBD, 0x01]))
                self.assertEqual(device.written[1][:2], bytes([0x01, 0xB0]))
                self.assertTrue(state["connected"])
                self.assertEqual(state["battery"], 28)

                device = FakeDevice()
                headset.apply(device, state, "volume", "75")
                self.assertEqual(device.written, [bytes([0x01, 0x25, 14]) + bytes(61)])
                self.assertEqual(headset.public(state)["volume"], 75)
                self.assertEqual(json.loads(Path(folder, "david-headset/state.json").read_text())["volume_raw"], 14)

                headset.handle_line(device, state, "volume down 10\n")
                self.assertEqual(device.written[-1][:3], bytes([0x01, 0x25, headset.volume_raw(65)]))
                headset.handle_line(device, state, "set eq-band 4 30\n")
                self.assertEqual(len(device.features), 1)
                self.assertEqual(struct.unpack_from("<HBbH", device.features[-1], 88), (250, 1, 50, 1410))
                self.assertFalse(any(frame[1] == 0x31 for frame in device.written))
                self.assertEqual(state["eq_bands"][3], 30)
                self.assertEqual(state["eq_bands"][0], 20)
                headset.handle_line(device, state, "set eq-flat 1\n")
                self.assertEqual(state["eq_bands"], [20] * 10)
                with self.assertRaises(headset.HeadsetError):
                    headset.handle_line(device, state, "dance")

    def test_stale_monitor_keeps_the_other_monitors_band_edit(self):
        with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, {"XDG_STATE_HOME": folder}):
            first, second = headset.fresh_state(), headset.fresh_state()
            device = FakeDevice()
            headset.apply(device, first, "eq-band", "1:30")
            headset.apply(device, second, "eq-band", "3:24")
            self.assertEqual(second["eq_bands"], [30, 20, 24] + [20] * 7)
            self.assertEqual(struct.unpack_from("<HBbH", device.features[-1], 70), (32, 1, 50, 1410))
            # A battery/volume event in the first helper must not replace the
            # EQ curve with the copy it cached before the second helper's edit.
            changed = headset.parse_event(bytes.fromhex("072519"), first)
            headset.save(first, changed)
            self.assertEqual(headset.load_saved()["eq_bands"], second["eq_bands"])

    def test_failed_eq_transfer_does_not_save_or_display_requested_gains(self):
        with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, {"XDG_STATE_HOME": folder}):
            original = [20] * 10
            headset.save({"eq_bands": original})
            state = headset.fresh_state()
            device = FakeDevice()
            with patch.object(device, "write_feature", side_effect=headset.HeadsetError("transfer failed")):
                with self.assertRaisesRegex(headset.HeadsetError, "transfer failed"):
                    headset.apply(device, state, "eq-band", "3:24")
            self.assertEqual(state["eq_bands"], original)
            self.assertEqual(headset.load_saved()["eq_bands"], original)
            self.assertEqual(device.written, [])

    def test_settings_saved_by_another_instance_are_folded_in(self):
        with tempfile.TemporaryDirectory() as folder:
            with patch.dict(os.environ, {"XDG_STATE_HOME": folder}):
                state = {"volume_raw": None, "eq_bands": None}
                seen = headset.sync_saved(state, None)
                self.assertIsNone(seen)
                self.assertIsNone(state["volume_raw"])
                headset.save({"volume_raw": 20, "sidetone": 4})
                seen = headset.sync_saved(state, seen)
                self.assertEqual((state["volume_raw"], state["sidetone"]), (20, 4))
                self.assertIsNone(state["eq_bands"])
                state["volume_raw"] = 30
                self.assertEqual(headset.sync_saved(state, seen), seen)
                self.assertEqual(state["volume_raw"], 30)

    def test_relative_volume_needs_a_known_level(self):
        with self.assertRaises(headset.HeadsetError):
            headset.nudged_volume({"volume_raw": None}, "up", 4)
        self.assertEqual(headset.nudged_volume({"volume_raw": 25}, "up", 4), "59")
        self.assertEqual(headset.nudged_volume({"volume_raw": 0}, "up", 4), "100")


class FeatureTransportTests(unittest.TestCase):
    def test_eq_uses_set_feature_ioctl_instead_of_output_write(self):
        device = object.__new__(headset.Device)
        device.fd = 123
        with patch.object(headset.fcntl, "ioctl", return_value=1036) as ioctl, patch.object(headset.os, "write") as write:
            device.write_feature(EQ_PLUS_2_AT_125)
        ioctl.assert_called_once_with(123, 0xC40C4806, bytearray(EQ_PLUS_2_AT_125), True)
        write.assert_not_called()

    def test_feature_transfer_errors_are_reported(self):
        device = object.__new__(headset.Device)
        device.fd = 123
        with patch.object(headset.fcntl, "ioctl", return_value=64):
            with self.assertRaisesRegex(headset.HeadsetError, "short EQ feature write"):
                device.write_feature(EQ_PLUS_2_AT_125)
        with patch.object(headset.fcntl, "ioctl", side_effect=OSError("USB failure")):
            with self.assertRaisesRegex(headset.HeadsetError, "could not apply the headset EQ"):
                device.write_feature(EQ_PLUS_2_AT_125)


if __name__ == "__main__":
    unittest.main()
