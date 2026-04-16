package main

import (
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"time"
)

func main() {
	switch os.Args[1] {
	case "server":
		runServer()
	case "client":
		runClient()
	case "mtls-server":
		runMTLSServer()
	case "mtls-client":
		runMTLSClient()
	default:
		fmt.Println("Usage: go run main.go [server|client|mtls-server|mtls-client]")
		os.Exit(1)
	}
}

func runServer() {
	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "Hello, TLS! Protocol: %s, TLS: %v\n", r.Proto, r.TLS != nil)
		if r.TLS != nil {
			fmt.Fprintf(w, "TLS Version: 0x%04x\n", r.TLS.Version)
			fmt.Fprintf(w, "Cipher Suite: 0x%04x\n", r.TLS.CipherSuite)
			fmt.Fprintf(w, "Server Name: %s\n", r.TLS.ServerName)
		}
	})

	cfg := &tls.Config{
		MinVersion: tls.VersionTLS12,
		CurvePreferences: []tls.CurveID{
			tls.X25519,
			tls.CurveP256,
		},
		CipherSuites: []uint16{
			tls.TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,
			tls.TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
			tls.TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305,
			tls.TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305,
			tls.TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,
			tls.TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,
		},
	}

	srv := &http.Server{
		Addr:         ":8443",
		Handler:      mux,
		TLSConfig:    cfg,
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	log.Println("TLS server starting on :8443")
	log.Fatal(srv.ListenAndServeTLS(
		"../pki/certs/server/server.myapp.local-fullchain.crt",
		"../pki/certs/server/server.myapp.local.key",
	))
}

func runClient() {
	caCert, err := os.ReadFile("../pki/root-ca/ca.crt")
	if err != nil {
		log.Fatalf("Failed to read CA cert: %v", err)
	}

	caCertPool := x509.NewCertPool()
	caCertPool.AppendCertsFromPEM(caCert)

	cfg := &tls.Config{
		RootCAs:    caCertPool,
		MinVersion: tls.VersionTLS12,
	}

	client := &http.Client{
		Transport: &http.Transport{
			TLSClientConfig: cfg,
		},
		Timeout: 10 * time.Second,
	}

	resp, err := client.Get("https://server.myapp.local:8443/")
	if err != nil {
		log.Fatalf("Failed to connect: %v", err)
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	fmt.Printf("Response: %s", body)
	fmt.Printf("TLS Version: %x\n", resp.TLS.Version)
	fmt.Printf("Cipher Suite: %x\n", resp.TLS.CipherSuite)
}

func runMTLSServer() {
	caCert, err := os.ReadFile("../pki/root-ca/ca.crt")
	if err != nil {
		log.Fatalf("Failed to read CA cert: %v", err)
	}

	caCertPool := x509.NewCertPool()
	caCertPool.AppendCertsFromPEM(caCert)

	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.TLS != nil && len(r.TLS.PeerCertificates) > 0 {
			cert := r.TLS.PeerCertificates[0]
			fmt.Fprintf(w, "Hello, mTLS! Client CN: %s\n", cert.Subject.CommonName)
			fmt.Fprintf(w, "Client Organization: %s\n", cert.Subject.Organization)
		} else {
			fmt.Fprintf(w, "Hello! No client certificate.\n")
		}
	})

	cfg := &tls.Config{
		ClientAuth: tls.RequireAndVerifyClientCert,
		ClientCAs:  caCertPool,
		MinVersion: tls.VersionTLS12,
		CurvePreferences: []tls.CurveID{
			tls.X25519,
			tls.CurveP256,
		},
		CipherSuites: []uint16{
			tls.TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,
			tls.TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
			tls.TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,
			tls.TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,
		},
	}

	srv := &http.Server{
		Addr:         ":8444",
		Handler:      mux,
		TLSConfig:    cfg,
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 10 * time.Second,
	}

	log.Println("mTLS server starting on :8444")
	log.Fatal(srv.ListenAndServeTLS(
		"../pki/certs/server/server.myapp.local-fullchain.crt",
		"../pki/certs/server/server.myapp.local.key",
	))
}

func runMTLSClient() {
	caCert, err := os.ReadFile("../pki/root-ca/ca.crt")
	if err != nil {
		log.Fatalf("Failed to read CA cert: %v", err)
	}

	caCertPool := x509.NewCertPool()
	caCertPool.AppendCertsFromPEM(caCert)

	clientCert, err := tls.LoadX509KeyPair(
		"../pki/certs/client/client.myapp.local.crt",
		"../pki/certs/client/client.myapp.local.key",
	)
	if err != nil {
		log.Fatalf("Failed to load client cert: %v", err)
	}

	cfg := &tls.Config{
		RootCAs:      caCertPool,
		Certificates: []tls.Certificate{clientCert},
		MinVersion:   tls.VersionTLS12,
	}

	client := &http.Client{
		Transport: &http.Transport{
			TLSClientConfig: cfg,
		},
		Timeout: 10 * time.Second,
	}

	resp, err := client.Get("https://server.myapp.local:8444/")
	if err != nil {
		log.Fatalf("Failed to connect: %v", err)
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	fmt.Printf("Response: %s", body)
}
