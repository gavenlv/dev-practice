const https = require("https");
const fs = require("fs");
const path = require("path");

const PKI_DIR = path.resolve(__dirname, "../../pki");

function createTLSServer(port = 8443) {
  const options = {
    key: fs.readFileSync(
      path.join(PKI_DIR, "certs/server/server.myapp.local.key")
    ),
    cert: fs.readFileSync(
      path.join(PKI_DIR, "certs/server/server.myapp.local-fullchain.crt")
    ),
    minVersion: "TLSv1.2",
    ciphers: "ECDHE+AESGCM:ECDHE+CHACHA20:DHE+AESGCM:DHE+CHACHA20",
    honorCipherOrder: true,
  };

  const server = https.createServer(options, (req, res) => {
    res.writeHead(200, { "Content-Type": "text/plain" });
    res.end("Hello, TLS from Node.js!\n");
  });

  server.listen(port, () => {
    console.log(`TLS server listening on https://localhost:${port}`);
  });

  return server;
}

function createTLSClient(host = "server.myapp.local", port = 8443) {
  const ca = fs.readFileSync(path.join(PKI_DIR, "root-ca/ca.crt"));

  const options = {
    hostname: host,
    port: port,
    path: "/",
    method: "GET",
    ca: ca,
    minVersion: "TLSv1.2",
    rejectUnauthorized: true,
  };

  const req = https.request(options, (res) => {
    let data = "";
    res.on("data", (chunk) => {
      data += chunk;
    });
    res.on("end", () => {
      console.log(`Response: ${data}`);
      console.log(`TLS Version: ${res.socket.getProtocol?.() || "N/A"}`);
      console.log(
        `Cipher: ${res.socket.getCipher?.()?.name || "N/A"}`
      );
    });
  });

  req.on("error", (e) => {
    console.error(`Request error: ${e.message}`);
  });

  req.end();
}

function createMTLSServer(port = 8444) {
  const options = {
    key: fs.readFileSync(
      path.join(PKI_DIR, "certs/server/server.myapp.local.key")
    ),
    cert: fs.readFileSync(
      path.join(PKI_DIR, "certs/server/server.myapp.local-fullchain.crt")
    ),
    ca: fs.readFileSync(path.join(PKI_DIR, "root-ca/ca.crt")),
    requestCert: true,
    rejectUnauthorized: true,
    minVersion: "TLSv1.2",
    ciphers: "ECDHE+AESGCM:ECDHE+CHACHA20:DHE+AESGCM:DHE+CHACHA20",
  };

  const server = https.createServer(options, (req, res) => {
    const clientCert = req.socket.getPeerCertificate();
    res.writeHead(200, { "Content-Type": "text/plain" });
    res.end(
      `Hello, mTLS! Client CN: ${clientCert.subject?.CN || "Unknown"}\n`
    );
  });

  server.listen(port, () => {
    console.log(`mTLS server listening on https://localhost:${port}`);
  });

  return server;
}

function createMTLSClient(host = "server.myapp.local", port = 8444) {
  const options = {
    hostname: host,
    port: port,
    path: "/",
    method: "GET",
    ca: fs.readFileSync(path.join(PKI_DIR, "root-ca/ca.crt")),
    key: fs.readFileSync(
      path.join(PKI_DIR, "certs/client/client.myapp.local.key")
    ),
    cert: fs.readFileSync(
      path.join(PKI_DIR, "certs/client/client.myapp.local.crt")
    ),
    minVersion: "TLSv1.2",
    rejectUnauthorized: true,
  };

  const req = https.request(options, (res) => {
    let data = "";
    res.on("data", (chunk) => {
      data += chunk;
    });
    res.on("end", () => {
      console.log(`Response: ${data}`);
    });
  });

  req.on("error", (e) => {
    console.error(`Request error: ${e.message}`);
  });

  req.end();
}

const command = process.argv[2];

switch (command) {
  case "server":
    createTLSServer();
    break;
  case "client":
    createTLSClient();
    break;
  case "mtls-server":
    createMTLSServer();
    break;
  case "mtls-client":
    createMTLSClient();
    break;
  default:
    console.log(
      "Usage: node tls-demo.js [server|client|mtls-server|mtls-client]"
    );
    process.exit(1);
}
