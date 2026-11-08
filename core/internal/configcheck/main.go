//go:build slm_bind

// Starts Xray and mihomo with configs written by tools/ConfigDump (the app's own generators).
package main

import (
	"fmt"
	"os"

	slmcore "github.com/slmtune/slmtune-ios/core"
)

func main() {
	dir := os.Args[1]
	fail := false
	xray, _ := os.ReadFile(dir + "/xray.json")
	err := slmcore.StartXray("check", string(xray))
	fmt.Println("xray config:", err)
	fail = fail || err != nil
	mihomo, _ := os.ReadFile(dir + "/mihomo.json")
	home, _ := os.MkdirTemp("", "mihomo")
	err = slmcore.StartMihomo(home, string(mihomo))
	fmt.Println("mihomo config:", err)
	fail = fail || err != nil
	slmcore.StopAll()
	if fail {
		os.Exit(1)
	}
}
