"""Loopback-only, synthetic browser integration fixtures. Never stores submitted data."""
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path

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
        if self.path.startswith('/download'):
            self.send_header('Content-Type','application/octet-stream')
            self.send_header('Content-Disposition','attachment; filename="browser-fixture.txt"')
            self.end_headers(); self.wfile.write(b'Synthetic browser download.\n'); return
        self.send_header('Content-Type','text/html'); self.end_headers()
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
