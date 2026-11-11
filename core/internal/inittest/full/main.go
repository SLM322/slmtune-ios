//go:build slm_bind

// What the VPN extension does first, as a plain program: all package inits (libbox + Xray + mihomo + transports),
// then libbox.Setup. Run on the iOS simulator in CI; a panic here is the extension's launch crash.
package main

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"

	"github.com/sagernet/sing-box/experimental/libbox"
	slmcore "github.com/slmtune/slmtune-ios/core"
)

func main() {
	fmt.Println("init ok:", libbox.Version(), slmcore.Version(), runtime.GOOS)
	base := filepath.Join(os.TempDir(), "slm-inittest-full")
	err := libbox.Setup(&libbox.SetupOptions{
		BasePath: base, WorkingPath: filepath.Join(base, "work"), TempPath: filepath.Join(base, "tmp"),
		LogMaxLines: 2000, OomKillerEnabled: true,
	})
	if err != nil {
		fmt.Println("setup:", err)
		os.Exit(1)
	}
	var m runtime.MemStats
	runtime.ReadMemStats(&m)
	fmt.Printf("setup ok; Go heap %d MB, sys %d MB\n", m.HeapAlloc>>20, m.Sys>>20)
}
