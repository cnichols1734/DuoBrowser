"""Loopback-only, synthetic browser integration fixtures. Never stores submitted data."""
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path
import struct, zlib, time
from urllib.parse import urlsplit, urlparse, parse_qs
from threading import Event, Lock

FRAME_REQUESTS = {}
FRAME_LOCK = Lock()

class DownloadGate:
    """Two bounded fixture attempts; release may arrive before the retry request."""
    def __init__(self):
        self.events = [Event(), Event()]
        self.attempts = 0

    def begin(self):
        self.attempts += 1
        return self.events[self.attempts - 1] if self.attempts <= 2 else None

DOWNLOAD_GATES = {}
DOWNLOAD_GATE_LOCK = Lock()

def download_gate(token):
    with DOWNLOAD_GATE_LOCK:
        if token not in DOWNLOAD_GATES:
            if len(DOWNLOAD_GATES) >= 16: return None
            DOWNLOAD_GATES[token] = DownloadGate()
        return DOWNLOAD_GATES[token]

PAGE = '''<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<link rel="icon" sizes="16x16" href="/favicon.ico"><link rel="apple-touch-icon" sizes="192x192" href="/touch-icon.png"><title>Browser checks</title><style>body{font:18px -apple-system;margin:16px}button,a,input{min-height:44px;margin:8px}footer{position:fixed;bottom:0;background:#aee;width:100%;left:0;height:44px}main{height:1800px}</style>
<h1>Browser checks</h1><input id="kept" placeholder="Preserved input"><a href="/next">Next page</a>
<button onclick="alert('Synthetic alert')">Alert</button><button onclick="document.querySelector('#result').textContent=confirm('Synthetic confirm')">Confirm</button>
<button onclick="document.querySelector('#result').textContent=prompt('Synthetic prompt','hello')">Prompt</button>
<form id="post" action="/post" method="POST" target="_blank" rel="opener"><input name="value" value="synthetic-post"><button>POST new window</button></form>
<a href="/download" download>Download fixture</a><input type="file" multiple><input type="file" accept="image/*">
<p id="result"></p><main><p>Find this browser fixture.</p></main><footer><button onclick="this.textContent='Footer works'">Footer action</button></footer>'''
class Handler(BaseHTTPRequestHandler):
    failed_downloads = set()
    def log_message(self, *_): pass
    def do_GET(self):
        self.send_response(200)
        path = urlsplit(self.path)
        if path.path.startswith('/download'):
            print('Synthetic download request: ' + path.path[:64], flush=True)
        query = parse_qs(path.query)
        gate_token = query.get('gate', [''])[0][:64]
        if path.path == '/download-release' and gate_token:
            gate = download_gate(gate_token)
            attempt = query.get('attempt', [''])[0]
            if gate and attempt in ('1', '2'): gate.events[int(attempt) - 1].set()
            self.send_header('Content-Type', 'text/plain'); self.send_header('Cache-Control', 'no-store')
            self.end_headers(); self.wfile.write(b'released' if gate and attempt in ('1', '2') else b'rejected'); return
        token = parse_qs(path.query).get('token', [''])[0][:64]
        if path.path in ('/frame-ad', '/scope-probe', '/scope-negative', '/socket-probe') and token:
            with FRAME_LOCK:
                if len(FRAME_REQUESTS) >= 128: FRAME_REQUESTS.clear()
                FRAME_REQUESTS[token] = FRAME_REQUESTS.get(token, 0) + 1
        if path.path == '/frame-count':
            with FRAME_LOCK: count = FRAME_REQUESTS.get(token, 0)
            self.send_header('Content-Type', 'text/plain'); self.send_header('Cache-Control', 'no-store')
            self.end_headers(); self.wfile.write(str(count).encode()); return
        if self.path.startswith('/reader-photo-') or self.path in ('/favicon.ico', '/touch-icon.png'):
            if self.path in ('/favicon.ico', '/touch-icon.png') and (self.headers.get('Cookie') or self.headers.get('Authorization')):
                self.end_headers(); self.wfile.write(b'Unexpected credentials'); return
            # Synthetic raster fixture, not captured browsing content.
            width, height = (16, 16) if self.path == "/favicon.ico" else ((192, 192) if self.path == "/touch-icon.png" else (320, 180))
            color = (36, 122, 165) if 'one' in self.path else (185, 108, 64)
            raw = b''.join(b'\x00' + bytes(color) * width for _ in range(height))
            def chunk(kind, payload):
                return struct.pack('!I', len(payload)) + kind + payload + struct.pack('!I', zlib.crc32(kind + payload))
            png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!2I5B', width, height, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')
            self.send_header('Content-Type', 'image/png'); self.end_headers(); self.wfile.write(png); return
        if self.path.startswith(('/download-slow', '/download-retry', '/download-chunked')):
            authorized = 'duo-download=synthetic' in self.headers.get('Cookie', '')
            payload = (b'Authenticated synthetic download.\n' if authorized else b'No cookie.\n') * 16000
            self.send_header('Content-Type', 'application/octet-stream')
            self.send_header('Content-Disposition', 'attachment; filename="download-progress.txt"')
            if not self.path.startswith('/download-chunked'): self.send_header('Content-Length', str(len(payload)))
            self.end_headers()
            token = parse_qs(urlparse(self.path).query).get('case', ['default'])[0]
            if self.path.startswith('/download-retry') and token not in self.failed_downloads:
                self.failed_downloads.add(token)
                self.wfile.write(payload[:4096]); self.wfile.flush(); self.close_connection = True; return
            gate = download_gate(gate_token) if gate_token else None
            with DOWNLOAD_GATE_LOCK:
                attempt = gate.begin() if gate else None
                attempt_number = gate.attempts if gate else 0
            final_attempt = 1 if query.get('gate-attempts', ['2'])[0] == '1' else 2
            expired = False
            try:
                for offset in range(0, len(payload), 8192):
                    self.wfile.write(payload[offset:offset+8192]); self.wfile.flush()
                    if gate_token and offset == 57344:
                        # Preserve an observable in-progress transfer until the harness cancels/releases it.
                        # Expiry interrupts the transfer rather than silently passing the test.
                        if attempt is None or not attempt.wait(60):
                            expired = True
                            self.close_connection = True; return
                    if not gate_token: time.sleep(0.15)
            except (BrokenPipeError, ConnectionResetError): pass
            finally:
                # An early canceled first response still owns attempt 1. Its release must not
                # recreate the registry entry and accidentally pre-release the retry's gate.
                if gate and (attempt_number >= final_attempt or attempt is None or expired):
                    with DOWNLOAD_GATE_LOCK:
                        if DOWNLOAD_GATES.get(gate_token) is gate: DOWNLOAD_GATES.pop(gate_token)
            return
        if self.path.startswith('/download-too-large'):
            self.send_header('Content-Type', 'application/octet-stream')
            self.send_header('Content-Disposition', 'attachment; filename="oversized.bin"')
            self.send_header('Content-Length', str(1073741825))
            self.end_headers(); return
        if self.path.startswith('/download-inline'):
            self.send_header('Content-Type', 'text/plain')
            self.send_header('Content-Disposition', 'inline; filename="inline.txt"')
            self.end_headers(); self.wfile.write(b'Inline document remains a webpage.'); return
        if self.path.startswith('/download'):
            self.send_header('Content-Type','application/octet-stream')
            self.send_header('Content-Disposition','attachment; filename="browser-fixture.txt"')
            self.end_headers(); self.wfile.write(b'Synthetic browser download.\n'); return
        self.send_header('Content-Type','text/html'); self.send_header('Access-Control-Allow-Origin','*'); self.end_headers()
        if path.path in ('/scoped-frame', '/scoped-parent', '/frame-exception'):
            self.wfile.write(b'''<!doctype html><meta name="viewport" content="width=device-width"><title>Scoped frame fixture</title><body><script>
            const params=new URLSearchParams(location.search),token=params.get('token');
            if(location.pathname==='/frame-exception')parent.postMessage({token,loaded:true},'*');
            else if(location.pathname==='/scoped-parent'){
                const child=document.createElement('iframe');
                window.addEventListener('message',event=>{if(event.source===child.contentWindow&&event.data?.token===token)parent.postMessage(event.data,'*')});
                child.src='http://127.0.0.1:8765/scoped-frame?token='+encodeURIComponent(token);
                document.body ? document.body.append(child) : document.documentElement.append(child);
            }else{
                const probe=params.get('negative')==='1'?'scope-negative':'scope-probe';
                fetch('http://127.0.0.1:8765/'+probe+'?token='+encodeURIComponent(token)).then(()=>false).catch(()=>true)
                    .then(blocked=>parent.postMessage({token,blocked},'*'));
            }
            </script>'''); return
        if self.path.startswith('/reader-article'):
            paragraph = 'Reading uses the available screen width and keeps photographs between the paragraphs where the author placed them. The original page and its draft stay untouched. '
            html = '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><title>Photo reading fixture</title><style>body{margin:16px;font:18px/1.5 sans-serif}img{width:100%;height:auto}figure{margin:0}main{padding-bottom:900px}</style><input id="kept" placeholder="Preserved draft"><main><article><h1>Photo reading fixture</h1><p>' + paragraph * 2 + '</p><figure><img src="/reader-photo-one.png" alt="First synthetic landscape" width="320" height="180"><figcaption>First photograph caption</figcaption></figure><p>' + paragraph * 2 + '</p><figure><img src="/reader-photo-two.png" alt="Second synthetic landscape" width="320" height="180"><figcaption>Second photograph caption</figcaption></figure><p>' + paragraph * 2 + '</p></article></main>'
            self.wfile.write(html.encode()); return
        if self.path.startswith('/upgrades'):
            paragraph = 'A thoughtful browser makes room for the page. Reader keeps the original document intact, while workspaces organize research and private browsing remains separate. ' * 4
            self.wfile.write(('<meta name="viewport" content="width=device-width,initial-scale=1"><title>A quieter way to browse</title><style>body{font:18px -apple-system;margin:24px}p{line-height:1.6}input,a{min-height:44px}article{max-width:700px}</style><input id="kept" placeholder="Synthetic draft"><a href="/preview">Preview this reference</a><article><h1>A quieter way to browse</h1><p>'+paragraph+'</p><h2>Keep your place</h2><p>'+paragraph+'</p><form><p>FORM SECRET</p></form></article>').encode())
            return
        if self.path.startswith('/nested-news'):
            self.wfile.write((Path(__file__).parent / 'Fixtures' / 'nested-news.html').read_bytes())
            return
        if self.path.startswith('/settling'):
            self.wfile.write((Path(__file__).parent / 'Fixtures' / 'settling.html').read_bytes())
        elif self.path.startswith('/reading'):
            self.wfile.write(b'<meta name="viewport" content="width=device-width"><title>Reading fixture</title><main style="height:2400px">Synthetic reading page</main>')
        elif self.path.startswith('/memory'):
            self.wfile.write(b'<meta name="viewport" content="width=device-width"><title>Memory fixture</title><input id="kept"><main style="height:2400px">Synthetic page</main>')
        else: self.wfile.write(PAGE.encode())
    def do_POST(self):
        if self.path.startswith('/download-post'):
            self.rfile.read(min(4096, int(self.headers.get('Content-Length', '0'))))
            self.send_response(200)
            self.send_header('Content-Type', 'application/octet-stream')
            self.send_header('Content-Disposition', 'attachment; filename="post-result.txt"')
            self.send_header('Content-Length', '1000')
            self.end_headers(); self.wfile.write(b'Partial POST response.'); self.close_connection = True; return
        body=self.rfile.read(min(4096,int(self.headers.get('Content-Length','0'))))
        self.send_response(200); self.send_header('Content-Type','text/html'); self.end_headers()
        self.wfile.write(b'<title>POST child</title><p id="received">'+body.replace(b'<',b'&lt;')+b'</p><script>if(opener)opener.postReceived=true;</script>')
if __name__ == '__main__':
    import sys, ssl
    server = ThreadingHTTPServer(('127.0.0.1', 8443 if len(sys.argv) == 3 else 8765), Handler)
    if len(sys.argv) == 3:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(sys.argv[1], sys.argv[2])
        server.socket = context.wrap_socket(server.socket, server_side=True)
    server.serve_forever()
