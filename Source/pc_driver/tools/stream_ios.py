"""Serve the latest Windows desktop frame to StormVR for iPhone."""

import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from ipaddress import IPv4Address
import secrets
import subprocess
import sys
import threading


MAX_JPEG_BYTES = 8 * 1024 * 1024


class Frames:
    def __init__(self):
        self.condition = threading.Condition()
        self.image = None
        self.next_id = 1
        self.etag = ""
        self.ended = False

    def capture(self, pipe):
        pending = bytearray()
        try:
            while chunk := pipe.read1(64 * 1024):
                pending.extend(chunk)
                while pending:
                    start = pending.find(b"\xff\xd8")
                    if start < 0:
                        del pending[:-1]
                        break
                    del pending[:start]
                    end = pending.find(b"\xff\xd9", 2)
                    if end < 0:
                        if len(pending) > MAX_JPEG_BYTES:
                            del pending[:-1]
                        break
                    if end + 2 <= MAX_JPEG_BYTES:
                        frame = bytes(pending[:end + 2])
                        with self.condition:
                            self.etag = f'"{self.next_id}"'
                            self.next_id += 1
                            self.image = frame
                            self.condition.notify_all()
                    del pending[:end + 2]
        finally:
            with self.condition:
                self.ended = True
                self.condition.notify_all()

    def latest(self, after):
        with self.condition:
            self.condition.wait_for(
                lambda: self.ended or (self.image is not None and self.etag != after),
                timeout=2,
            )
            if self.ended:
                return 503, "", b""
            if self.image is None or self.etag == after:
                return 204, "", b""
            return 200, self.etag, self.image


class VideoServer(ThreadingHTTPServer):
    def __init__(self, address, frames, token):
        self.frames = frames
        self.authorization = f"Bearer {token}".encode("ascii")
        super().__init__(address, VideoRequest)

    def get_request(self):
        connection, address = super().get_request()
        connection.settimeout(5)
        return connection, address


class VideoRequest(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        authorization = self.headers.get("Authorization", "").encode("latin-1")
        if self.path != "/frame.jpg":
            status, etag, image = 404, "", b""
        elif not secrets.compare_digest(authorization, self.server.authorization):
            status, etag, image = 401, "", b""
        else:
            status, etag, image = self.server.frames.latest(self.headers.get("If-None-Match"))
        try:
            self.send_response(status)
            self.send_header("Cache-Control", "no-store")
            if status != 204:
                self.send_header("Content-Length", str(len(image)))
            if image:
                self.send_header("Content-Type", "image/jpeg")
                self.send_header("ETag", etag)
            self.end_headers()
            if image:
                self.wfile.write(image)
        except (ConnectionError, TimeoutError):
            self.close_connection = True

    def log_message(self, format, *args):
        pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bind", required=True, type=IPv4Address, help="IPv4 do PC na rede local")
    parser.add_argument("--port", type=int, default=8089)
    parser.add_argument("--size", metavar="LARGURAxALTURA", help="tamanho original do monitor SteamVR")
    parser.add_argument("--x", type=int, default=0, help="deslocamento X do monitor em pixels")
    parser.add_argument("--y", type=int, default=0, help="deslocamento Y do monitor em pixels")
    parser.add_argument("--fps", type=int, default=30)
    parser.add_argument("--width", type=int, default=1600, help="largura máxima do vídeo enviado")
    parser.add_argument("--ffmpeg", default="ffmpeg")
    args = parser.parse_args()
    if args.bind.is_unspecified or args.bind.is_multicast:
        parser.error("--bind precisa ser o IPv4 específico da interface local")
    if not 1024 <= args.port <= 65535 or not 1 <= args.fps <= 60 or not 320 <= args.width <= 3072:
        parser.error("use porta 1024–65535, FPS 1–60 e largura 320–3072")
    if (args.x or args.y) and not args.size:
        parser.error("--x e --y requerem --size")

    command = [args.ffmpeg, "-nostdin", "-hide_banner", "-loglevel", "error", "-f", "gdigrab",
               "-framerate", str(args.fps), "-draw_mouse", "0"]
    if args.size:
        command += ["-offset_x", str(args.x), "-offset_y", str(args.y), "-video_size", args.size]
    command += [
        "-i", "desktop", "-an", "-vf", f"scale=w='min(iw,{args.width})':h=-2",
        "-c:v", "mjpeg", "-q:v", "5", "-threads", "1", "-f", "image2pipe", "pipe:1",
    ]

    frames = Frames()
    token = secrets.token_urlsafe(12)
    try:
        with VideoServer((str(args.bind), args.port), frames, token) as server:
            with subprocess.Popen(command, stdout=subprocess.PIPE) as ffmpeg:
                capture = threading.Thread(target=frames.capture, args=(ffmpeg.stdout,), daemon=True)
                capture.start()
                print(f"StormVR em {args.bind}:{args.port} · Código do vídeo: {token}", flush=True)
                server.timeout = 0.5
                try:
                    while ffmpeg.poll() is None:
                        server.handle_request()
                finally:
                    if ffmpeg.poll() is None:
                        ffmpeg.terminate()
                    capture.join(timeout=3)
                if ffmpeg.returncode:
                    print(f"A captura terminou com código {ffmpeg.returncode}.", file=sys.stderr)
                    return 1
    except KeyboardInterrupt:
        return 0
    except OSError as error:
        print(f"Falha ao iniciar captura: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
