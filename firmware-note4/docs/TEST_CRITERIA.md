# Hardware test criteria

The test implementation is in `components/zectrix_self_test`. Interactive
tests time out after approximately 60 seconds unless stated otherwise.

| Test | PASS criterion | Operator setup |
| --- | --- | --- |
| Wi-Fi RF | Generic mode: at least one 2.4 GHz AP found. Qualification mode: configured SSID observed three consecutive times at or above the RSSI threshold. | Provide a 2.4 GHz AP; configure SSID and threshold for production use. |
| Audio | Generated AFSK sequence is played, recorded by the microphone and decoded successfully. | Use a reasonably quiet space; do not cover speaker or microphone. |
| RTC | PCF8563 one-second countdown asserts its status flag or interrupt within the retry window. | No operator action. |
| Power | Charging is active, or the charger reports full while a valid battery measurement exceeds 97%; no-battery and fault states fail. | Connect a battery and USB power. |
| LED | Operator confirms that the power LED visibly blinks. | OK = PASS; DOWN press = FAIL. |
| Buttons | Correct sequence `OK`, `UP`, `DOWN` is received. UP/DOWN trigger on press; OK triggers on release. Wrong input restarts the sequence. | Follow the on-screen prompt. |
| NFC | User memory is backed up, a temporary URL NDEF message is written and read back, a phone field is detected, then the original bytes are restored. | Hold an NFC-capable phone near the antenna when prompted. |

## Controls during tests

- Hold OK for 1.5 seconds to cancel the current test and return.
- Hold DOWN for 3 seconds to request clear-and-shutdown.
- Run All records PASS/FAIL for each test and ends on a seven-item summary.

## Production recommendations

Generic Wi-Fi scan is intended for demonstrations only. Set
`CONFIG_ZECTRIX_DEMO_RF_TARGET_SSID` and choose an RSSI threshold that matches
the fixture before using RF results for qualification.

The LED test is intentionally visual. For a fully automated fixture, add an
optical sensor and replace the operator result with a measured threshold.

The NFC test is designed to preserve existing user data. Power must remain
stable through the restore step; a production fixture should also verify the
restored bytes after an interrupted-test recovery procedure.
