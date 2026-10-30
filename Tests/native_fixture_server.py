"""Loopback-only, synthetic browser integration fixtures. Never stores submitted data."""
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path
import struct, zlib

PAGE = '''<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>Browser checks</title><style>body{font:18px -apple-system;margin:16px}button,a,input{min-height:44px;margin:8px}footer{position:fixed;bottom:0;background:#aee;width:100%;left:0;height:44px}main{height:1800px}</style>
<h1>Browser checks</h1><input id="kept" placeholder="Preserved input"><a href="/next">Next page</a>
<button onclick="alert('Synthetic alert')">Alert</button><button onclick="document.querySelector('#result').textContent=confirm('Synthetic confirm')">Confirm</button>
<button onclick="document.querySelector('#result').textContent=prompt('Synthetic prompt','hello')">Prompt</button>
<form id="post" action="/post" method="POST" target="_blank" rel="opener"><input name="value" value="synthetic-post"><button>POST new window</button></form>
<a href="/download" download>Download fixture</a><input type="file" multiple><input type="file" accept="image/*">
<p id="result"></p><main><p>Find this browser fixture.</p></main><footer><button onclick="this.textContent='Footer works'">Footer action</button></footer>'''
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_): pass
    def do_GET(self):
        self.send_response(200)
        if self.path.startswith('/reader-photo-'):
            # Synthetic raster fixture, not captured browsing content.
            width, height = 320, 180
            color = (36, 122, 165) if 'one' in self.path else (185, 108, 64)
            raw = b''.join(b'\x00' + bytes(color) * width for _ in range(height))
            def chunk(kind, payload):
                return struct.pack('!I', len(payload)) + kind + payload + struct.pack('!I', zlib.crc32(kind + payload))
            png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!2I5B', width, height, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')
            self.send_header('Content-Type', 'image/png'); self.end_headers(); self.wfile.write(png); return
        if self.path.startswith('/download'):
            self.send_header('Content-Type','application/octet-stream')
            self.send_header('Content-Disposition','attachment; filename="browser-fixture.txt"')
            self.end_headers(); self.wfile.write(b'Synthetic browser download.\n'); return
        self.send_header('Content-Type','text/html'); self.send_header('Access-Control-Allow-Origin','*'); self.end_headers()
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
