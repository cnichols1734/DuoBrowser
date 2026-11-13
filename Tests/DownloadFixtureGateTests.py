"""Synthetic transfer gates do not depend on scheduler timing or open a server."""
from native_fixture_server import DownloadGate, DOWNLOAD_GATES, Handler, download_gate

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

# Execute the actual response lifecycle without opening ports or waiting on wall-clock time.
DOWNLOAD_GATES.clear()
class Sink:
    def __init__(self, interrupt=False):
        self.data = bytearray()
        self.interrupt = interrupt
    def write(self, data):
        if self.interrupt and self.data: raise BrokenPipeError()
        self.data.extend(data)
    def flush(self): pass

def response(path, interrupt=False):
    handler = Handler.__new__(Handler)
    handler.path = path
    handler.headers = {'Cookie': 'duo-download=synthetic'}
    handler.wfile = Sink(interrupt)
    handler.send_response = lambda *_: None
    handler.send_header = lambda *_: None
    handler.end_headers = lambda: None
    handler.do_GET()
    return handler

response('/download-slow?gate=early-cancel', interrupt=True)
retained = DOWNLOAD_GATES.get('early-cancel')
assert retained is not None and retained.attempts == 1
response('/download-release?gate=early-cancel&attempt=1')
assert retained.events[0].is_set() and not retained.events[1].is_set()
response('/download-release?gate=early-cancel&attempt=2')
retry = response('/download-slow?gate=early-cancel')
assert len(retry.wfile.data) > 65536 and retry.wfile.data.startswith(b'Authenticated synthetic') and 'early-cancel' not in DOWNLOAD_GATES

class Expired:
    def wait(self, _): return False
expired = download_gate('expired')
expired.events[0] = Expired()
interrupted = response('/download-slow?gate=expired')
assert interrupted.close_connection and 'expired' not in DOWNLOAD_GATES
print('11 synthetic download gate checks passed')
