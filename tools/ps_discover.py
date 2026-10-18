"""Read-only PS Remote Play discovery probe (same SRCH packet chiaki / PS Remote Play send).

Broadcasts SRCH on the PS5 (9302) and PS4 (987) discovery ports and prints every reply.
A console answers "HTTP/1.1 200 Ok" when on and "HTTP/1.1 620 Server Standby" in rest mode
(only if rest mode keeps the network up).
"""
import socket
import sys
import time

TARGETS = sys.argv[1:] or ["255.255.255.255"]
PROBES = [
    (9302, b"SRCH * HTTP/1.1\ndevice-discovery-protocol-version:00030010\n"),  # PS5
    (987, b"SRCH * HTTP/1.1\ndevice-discovery-protocol-version:00020020\n"),   # PS4
]

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
sock.bind(("0.0.0.0", 0))
sock.settimeout(0.3)

replies = {}
for attempt in range(3):
    for target in TARGETS:
        for port, payload in PROBES:
            try:
                sock.sendto(payload, (target, port))
            except OSError as exc:
                print(f"send to {target}:{port} failed: {exc}")
    end = time.time() + 1.5
    while time.time() < end:
        try:
            data, (ip, port) = sock.recvfrom(4096)
        except socket.timeout:
            continue
        replies[(ip, port)] = data.decode(errors="replace")

if not replies:
    print("no console answered")
for (ip, port), text in sorted(replies.items()):
    print(f"== reply from {ip}:{port}")
    print(text.strip())
