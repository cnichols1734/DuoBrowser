"""Synthetic transfer gates do not depend on scheduler timing or open a server."""
from native_fixture_server import DownloadGate, DOWNLOAD_GATES, download_gate

gate = DownloadGate()
first = gate.begin()
assert first is not None and not first.wait(0.001)
gate.events[0].set()
assert first.wait(0) and not gate.events[1].is_set()
gate.events[1].set()  # Closing the source may release before WebKit starts the retry.
assert gate.begin().wait(0)
assert gate.begin() is None  # Unexpected extra attempts cannot bypass the two-step protocol.
assert download_gate('same') is download_gate('same')
assert all(download_gate(str(index)) is not None for index in range(15))
assert download_gate('overflow') is None and len(DOWNLOAD_GATES) == 16
print('7 synthetic download gate checks passed')
