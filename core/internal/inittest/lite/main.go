//go:build slm_bind

// The lite build's Go side (sing-box alone): package inits, then libbox.Setup. See ../full.
package main

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"

	"github.com/sagernet/sing-box/experimental/libbox"
)

func main() {
	fmt.Println("init ok:", libbox.Version(), runtime.GOOS)
	base := filepath.Join(os.TempDir(), "slm-inittest-lite")
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
