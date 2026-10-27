package main

import (
	"embed"
	"encoding/json"
	"io/fs"
	"log"
	"net/http"
	"os"
	"regexp"
	"time"
)

//go:embed static
var assets embed.FS

func handler(clientID string) http.Handler {
	files, _ := fs.Sub(assets, "static")
	mux := http.NewServeMux()
	mux.HandleFunc("GET /config.json", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"clientID": clientID})
	})
	mux.Handle("GET /", http.FileServer(http.FS(files)))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Referrer-Policy", "strict-origin-when-cross-origin")
		w.Header().Set("Cross-Origin-Opener-Policy", "same-origin-allow-popups")
		w.Header().Set("Content-Security-Policy", "default-src 'self'; script-src 'self' https://accounts.google.com/gsi/client; style-src 'self' https://accounts.google.com/gsi/style; frame-src https://accounts.google.com; connect-src 'self' https://accounts.google.com https://www.googleapis.com https://openidconnect.googleapis.com; img-src 'self' data:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'")
		mux.ServeHTTP(w, r)
	})
}
func main() {
	clientID := os.Getenv("GOOGLE_WEB_CLIENT_ID")
	if clientID != "" && !regexp.MustCompile(`^[0-9]+-[a-zA-Z0-9_-]+\.apps\.googleusercontent\.com$`).MatchString(clientID) {
		log.Fatal("GOOGLE_WEB_CLIENT_ID must be a web OAuth client ID")
	}
	address := os.Getenv("LISTEN_ADDR")
	if address == "" {
		address = "127.0.0.1:8080"
	}
	log.Printf("Yoteikan Web: http://%s", address)
	if clientID == "" {
		log.Print("Google login is unconfigured; demo is available")
	}
	server := &http.Server{Addr: address, Handler: handler(clientID), ReadHeaderTimeout: 10 * time.Second, IdleTimeout: 60 * time.Second}
	log.Fatal(server.ListenAndServe())
}
