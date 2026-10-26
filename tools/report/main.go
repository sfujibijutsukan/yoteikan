// report exports actual XCTest screenshot attachments to stable filenames.
// Usage: go run ./tools/report/main.go artifacts/Validation.xcresult docs/screenshots
package main

import (
	"encoding/json"
	"fmt"
	"html/template"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

type attachment struct {
	File string `json:"exportedFileName"`
	Name string `json:"suggestedHumanReadableName"`
}
type entry struct {
	Attachments []attachment `json:"attachments"`
}
type screen struct{ Name, File string }

func must(err error) {
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
func main() {
	if len(os.Args) != 3 {
		fmt.Fprintln(os.Stderr, "usage: report RESULT.xcresult OUTPUT_DIRECTORY")
		os.Exit(2)
	}
	result, out := os.Args[1], os.Args[2]
	must(os.MkdirAll(out, 0755))
	tmp, err := os.MkdirTemp("", "yoteikan-attachments-")
	must(err)
	defer os.RemoveAll(tmp)
	cmd := exec.Command("xcrun", "xcresulttool", "export", "attachments", "--path", result, "--output-path", tmp)
	if output, err := cmd.CombinedOutput(); err != nil {
		fmt.Fprintln(os.Stderr, string(output))
		must(err)
	}
	data, err := os.ReadFile(filepath.Join(tmp, "manifest.json"))
	must(err)
	var entries []entry
	must(json.Unmarshal(data, &entries))
	var screens []screen
	for _, e := range entries {
		for _, a := range e.Attachments {
			if !strings.HasSuffix(a.File, ".png") || len(a.Name) < 3 || a.Name[2] != '-' {
				continue
			}
			base := strings.SplitN(a.Name, "_", 2)[0]
			filename := base + ".png"
			data, err := os.ReadFile(filepath.Join(tmp, a.File))
			must(err)
			must(os.WriteFile(filepath.Join(out, filename), data, 0644))
			screens = append(screens, screen{base, filename})
			fmt.Println(filename)
		}
	}
	// Keep a complete gallery when a later visual check updates only some screens.
	files, err := os.ReadDir(out)
	must(err)
	screens = nil
	for _, file := range files {
		name := file.Name()
		if !file.IsDir() && len(name) > 3 && name[2] == '-' && strings.HasSuffix(name, ".png") {
			screens = append(screens, screen{strings.TrimSuffix(name, ".png"), name})
		}
	}
	sort.Slice(screens, func(i, j int) bool { return screens[i].Name < screens[j].Name })
	tmpl := template.Must(template.New("report").Parse(`<!doctype html><html lang="ja"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>予定館・実機能確認</title><style>body{background:#f7f5ed;color:#293b35;font:15px system-ui;margin:32px}h1{font-size:24px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:28px}figure{margin:0}img{width:100%;max-width:390px;border-radius:24px;box-shadow:0 8px 32px #293b3520}figcaption{margin:12px 0 20px}p{line-height:1.8}</style><h1>予定館 / シミュレーター動作確認</h1><p>iPhone 17e・iOS 27。XCTestで実際に操作した画面です。計画画面はサンプル予定、カレンダー画面はシミュレーターのEventKitに登録した検証用予定を使用しています。</p><div class="grid">{{range .}}<figure><a href="{{.File}}"><img src="{{.File}}" alt="{{.Name}}"></a><figcaption>{{.Name}}</figcaption></figure>{{end}}</div></html>`))
	f, err := os.Create(filepath.Join(out, "index.html"))
	must(err)
	defer f.Close()
	must(tmpl.Execute(f, screens))
}
