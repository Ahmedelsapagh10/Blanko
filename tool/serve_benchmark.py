"""Loopback-only benchmark server; optional isolation is not production hosting."""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, default=Path('build/web'))
    parser.add_argument('--port', type=int, default=8765)
    parser.add_argument('--isolated', action='store_true')
    args = parser.parse_args()
    if not args.directory.is_dir():
        parser.error('Benchmark build directory does not exist')

    class Handler(SimpleHTTPRequestHandler):
        def end_headers(self):
            self.send_header('Cache-Control', 'no-store')
            if args.isolated:
                self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
                self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
            super().end_headers()

    server = ThreadingHTTPServer(
        ('127.0.0.1', args.port), partial(Handler, directory=str(args.directory)))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
