// google-config writes the two public OAuth identifiers required by Google Sign-In.
package main

import (
	"flag"
	"fmt"
	"os"
	"regexp"
	"strings"
)

func main() {
	clientID := flag.String("client-id", "", "iOS OAuth client ID from Google Cloud")
	output := flag.String("output", "ios/Google.local.xcconfig", "local Xcode configuration file")
	flag.Parse()
	id := strings.TrimSpace(*clientID)
	if !regexp.MustCompile(`^[A-Za-z0-9_-]+\.apps\.googleusercontent\.com$`).MatchString(id) {
		fmt.Fprintln(os.Stderr, "有効なiOS用OAuthクライアントID（…apps.googleusercontent.com）を指定してください。")
		os.Exit(1)
	}
	fields := strings.Split(id, ".")
	for i, j := 0, len(fields)-1; i < j; i, j = i+1, j-1 {
		fields[i], fields[j] = fields[j], fields[i]
	}
	content := "// Local Google OAuth client identifiers. No client secret is needed.\nGOOGLE_CLIENT_ID = " + id + "\nGOOGLE_REVERSED_CLIENT_ID = " + strings.Join(fields, ".") + "\n"
	if err := os.WriteFile(*output, []byte(content), 0600); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Println("Googleログインの接続設定を作成しました:", *output)
}
