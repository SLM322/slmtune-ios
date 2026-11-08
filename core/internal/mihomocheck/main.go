//go:build slm_bind

// Feeds a config of the shape Engines.mihomoConfig produces to slmcore.StartMihomo.
package main

import (
	"fmt"
	"os"

	slmcore "github.com/slmtune/slmtune-ios/core"
)

func main() {
	b, _ := os.ReadFile(os.Args[1])
	dir, _ := os.MkdirTemp("", "m")
	err := slmcore.StartMihomo(dir, string(b))
	fmt.Println("mihomo:", err)
	slmcore.StopMihomo()
	if err != nil {
		os.Exit(1)
	}
}
