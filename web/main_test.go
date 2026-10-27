package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestConfigAndSecurityHeaders(t *testing.T) {
	h := handler("123-test.apps.googleusercontent.com")
	w := httptest.NewRecorder()
	h.ServeHTTP(w, httptest.NewRequest("GET", "/config.json", nil))
	var config map[string]string
	if err := json.Unmarshal(w.Body.Bytes(), &config); err != nil || config["clientID"] != "123-test.apps.googleusercontent.com" {
		t.Fatal("incorrect config", err)
	}
	if w.Header().Get("Cache-Control") != "no-store" || !strings.Contains(w.Header().Get("Content-Security-Policy"), "frame-ancestors 'none'") {
		t.Fatal("missing cache/security headers")
	}
	if w.Header().Get("Cross-Origin-Opener-Policy") != "same-origin-allow-popups" {
		t.Fatal("Google popup must remain usable")
	}
}
func TestEmbeddedAppAndNoSourceExposure(t *testing.T) {
	h := handler("")
	for _, path := range []string{"/", "/app.mjs", "/sync.mjs", "/style.css"} {
		w := httptest.NewRecorder()
		h.ServeHTTP(w, httptest.NewRequest("GET", path, nil))
		if w.Code != 200 {
			t.Fatalf("%s: %d", path, w.Code)
		}
	}
	for _, path := range []string{"/main.go", "/.env", "/../main.go"} {
		w := httptest.NewRecorder()
		h.ServeHTTP(w, httptest.NewRequest("GET", path, nil))
		if strings.Contains(w.Body.String(), "package main") {
			t.Fatal("server source exposed")
		}
	}
}

func TestExportForPages(t *testing.T) {
	dir := t.TempDir()
	if err := exportSite(dir, "123-web.apps.googleusercontent.com"); err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{"index.html", "app.mjs", "sync.mjs", "style.css", "config.json", ".nojekyll"} {
		if _, err := os.Stat(filepath.Join(dir, path)); err != nil {
			t.Fatal(err)
		}
	}
	h := http.FileServer(http.Dir(dir))
	for _, path := range []string{"/index.html", "/app.mjs", "/config.json"} {
		w := httptest.NewRecorder()
		h.ServeHTTP(w, httptest.NewRequest("GET", path, nil))
		if w.Code != 200 && w.Code != 301 {
			t.Fatalf("static %s: %d", path, w.Code)
		}
	}
	data, err := os.ReadFile(filepath.Join(dir, "index.html"))
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(data), `src="/app.mjs"`) || !strings.Contains(string(data), `src="app.mjs"`) {
		t.Fatal("assets must also work under a repository subpath")
	}
	config, _ := os.ReadFile(filepath.Join(dir, "config.json"))
	if !strings.Contains(string(config), "123-web.apps.googleusercontent.com") {
		t.Fatal("missing web client ID")
	}
	if _, err := os.Stat(filepath.Join(dir, "main.go")); !os.IsNotExist(err) {
		t.Fatal("server source should not be exported")
	}
}
