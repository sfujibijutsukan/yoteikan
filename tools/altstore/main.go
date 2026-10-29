// altstore builds an unsigned iPhone IPA for AltStore Classic to re-sign.
package main

import (
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
)

func run(name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
	return cmd.Run()
}

func build() error {
	output := flag.String("output", "artifacts/altstore/Yoteikan.ipa", "new IPA path (must not exist)")
	client := flag.String("client-id", "", "optional iOS Google OAuth client ID override")
	flag.Parse()
	if runtime.GOOS != "darwin" {
		return fmt.Errorf("MacとXcodeが必要です")
	}
	if flag.NArg() != 0 {
		return fmt.Errorf("不明な引数があります")
	}
	if _, err := os.Stat("ios/Yoteikan.xcodeproj"); err != nil {
		return fmt.Errorf("リポジトリのルートで実行してください: %w", err)
	}
	if *client != "" && !regexp.MustCompile(`^[A-Za-z0-9_-]+\.apps\.googleusercontent\.com$`).MatchString(*client) {
		return fmt.Errorf("iOS用OAuthクライアントIDが不正です")
	}
	target, err := filepath.Abs(*output)
	if err != nil {
		return err
	}
	if err = os.MkdirAll(filepath.Dir(target), 0755); err != nil {
		return err
	}
	// Reserve exclusively: never replace an existing installer on failure or success.
	reserved, err := os.OpenFile(target, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0644)
	if err != nil {
		return err
	}
	reserved.Close()
	success := false
	defer func() {
		if !success {
			os.Remove(target)
		}
	}()
	temp, err := os.MkdirTemp("", "yoteikan-altstore-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(temp)
	derived := filepath.Join(temp, "build")
	args := []string{"-project", "ios/Yoteikan.xcodeproj", "-scheme", "Yoteikan", "-configuration", "Release", "-destination", "generic/platform=iOS", "-derivedDataPath", derived, "build", "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY=", "PRODUCT_BUNDLE_IDENTIFIER=org.sfuji.yoteikan"}
	if *client != "" {
		reversed := "com.googleusercontent.apps." + strings.TrimSuffix(*client, ".apps.googleusercontent.com")
		args = append(args, "GOOGLE_CLIENT_ID="+*client, "GOOGLE_REVERSED_CLIENT_ID="+reversed)
	}
	if err = run("xcodebuild", args...); err != nil {
		return fmt.Errorf("iPhoneビルド失敗: %w", err)
	}
	payload := filepath.Join(temp, "Payload")
	if err = os.Mkdir(payload, 0755); err != nil {
		return err
	}
	app := filepath.Join(derived, "Build", "Products", "Release-iphoneos", "Yoteikan.app")
	if err = run("/usr/bin/ditto", app, filepath.Join(payload, "Yoteikan.app")); err != nil {
		return err
	}
	ipa := filepath.Join(temp, "Yoteikan.ipa")
	if err = run("/usr/bin/ditto", "-c", "-k", "--keepParent", "--norsrc", payload, ipa); err != nil {
		return err
	}
	data, err := os.ReadFile(ipa)
	if err != nil {
		return err
	}
	if err = os.WriteFile(target, data, 0644); err != nil {
		return err
	}
	success = true
	fmt.Println("AltStore用IPA:", target)
	fmt.Println("未署名です。iPhoneのAltStore Classicから追加してください。署名・更新はAltStoreとAltServerが行います。")
	return nil
}

func main() {
	if err := build(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
