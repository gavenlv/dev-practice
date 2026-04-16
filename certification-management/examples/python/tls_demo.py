import ssl
import socket
import subprocess
import sys
from pathlib import Path

PKI_DIR = Path(__file__).parent.parent.parent / "pki"


def create_tls_server(host="0.0.0.0", port=8443):
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(
        certfile=PKI_DIR / "certs" / "server" / "server.myapp.local-fullchain.crt",
        keyfile=PKI_DIR / "certs" / "server" / "server.myapp.local.key",
    )
    context.set_ciphers(
        "ECDHE+AESGCM:ECDHE+CHACHA20:DHE+AESGCM:DHE+CHACHA20"
    )
    context.options |= ssl.OP_NO_SSLv2
    context.options |= ssl.OP_NO_SSLv3
    context.options |= ssl.OP_NO_TLSv1
    context.options |= ssl.OP_NO_TLSv1_1

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind((host, port))
        sock.listen(5)
        print(f"TLS server listening on {host}:{port}")

        with context.wrap_socket(sock, server_side=True) as ssock:
            conn, addr = ssock.accept()
            print(f"Connection from {addr}")
            print(f"TLS Version: {conn.version()}")
            print(f"Cipher: {conn.cipher()}")
            data = conn.recv(1024)
            conn.sendall(b"Hello, TLS! " + data)


def create_tls_client(host="server.myapp.local", port=8443):
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_verify_locations(PKI_DIR / "root-ca" / "ca.crt")
    context.set_ciphers(
        "ECDHE+AESGCM:ECDHE+CHACHA20:DHE+AESGCM:DHE+CHACHA20"
    )

    with socket.create_connection((host, port)) as sock:
        with context.wrap_socket(sock, server_hostname=host) as ssock:
            print(f"TLS Version: {ssock.version()}")
            print(f"Cipher: {ssock.cipher()}")
            ssock.sendall(b"Hello from Python client!")
            data = ssock.recv(1024)
            print(f"Received: {data.decode()}")


def create_mtls_server(host="0.0.0.0", port=8444):
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(
        certfile=PKI_DIR / "certs" / "server" / "server.myapp.local-fullchain.crt",
        keyfile=PKI_DIR / "certs" / "server" / "server.myapp.local.key",
    )
    context.load_verify_locations(PKI_DIR / "root-ca" / "ca.crt")
    context.verify_mode = ssl.CERT_REQUIRED

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind((host, port))
        sock.listen(5)
        print(f"mTLS server listening on {host}:{port}")

        with context.wrap_socket(sock, server_side=True) as ssock:
            conn, addr = ssock.accept()
            print(f"Connection from {addr}")
            print(f"Client CN: {conn.getpeercert()['subject']}")
            data = conn.recv(1024)
            conn.sendall(b"Hello, mTLS! " + data)


def create_mtls_client(host="server.myapp.local", port=8444):
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_verify_locations(PKI_DIR / "root-ca" / "ca.crt")
    context.load_cert_chain(
        certfile=PKI_DIR / "certs" / "client" / "client.myapp.local.crt",
        keyfile=PKI_DIR / "certs" / "client" / "client.myapp.local.key",
    )

    with socket.create_connection((host, port)) as sock:
        with context.wrap_socket(sock, server_hostname=host) as ssock:
            print(f"TLS Version: {ssock.version()}")
            print(f"Cipher: {ssock.cipher()}")
            ssock.sendall(b"Hello from Python mTLS client!")
            data = ssock.recv(1024)
            print(f"Received: {data.decode()}")


def check_cert_expiry(domain, port=443):
    context = ssl.create_default_context()
    with socket.create_connection((domain, port)) as sock:
        with context.wrap_socket(sock, server_hostname=domain) as ssock:
            cert = ssock.getpeercert()
            print(f"Domain: {domain}")
            print(f"Subject: {cert['subject']}")
            print(f"Issuer: {cert['issuer']}")
            print(f"Not Before: {cert['notBefore']}")
            print(f"Not After: {cert['notAfter']}")
            print(f"SAN: {cert.get('subjectAltName', 'N/A')}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python tls_demo.py [server|client|mtls-server|mtls-client|check <domain>]")
        sys.exit(1)

    cmd = sys.argv[1]
    if cmd == "server":
        create_tls_server()
    elif cmd == "client":
        create_tls_client()
    elif cmd == "mtls-server":
        create_mtls_server()
    elif cmd == "mtls-client":
        create_mtls_client()
    elif cmd == "check":
        domain = sys.argv[2] if len(sys.argv) > 2 else "google.com"
        check_cert_expiry(domain)
    else:
        print(f"Unknown command: {cmd}")
