package main

import (
	"encoding/json"
	"net/http/httptest"
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
