//go:build slm_bind

// Keeps one in-process transport running and prints its port (for a desktop tor.exe test).
package main

import (
	"fmt"
	"os"
	"time"

	slmcore "github.com/slmtune/slmtune-ios/core"
)

type stdout struct{}

func (stdout) WriteLog(l string) { fmt.Println("pt log:", l) }

func main() {
	slmcore.SetLogWriter(stdout{})
	port, err := slmcore.StartTransport(os.Args[1], os.TempDir()+"/slm-pt")
	if err != nil {
		fmt.Println("error:", err)
		os.Exit(1)
	}
	fmt.Println("PORT", port)
	time.Sleep(10 * time.Minute)
}
