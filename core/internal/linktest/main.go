//go:build slm_bind

// Link check only: libbox and slmcore together in one Go binary (what gomobile bind produces).
package main

import (
	"fmt"

	"github.com/sagernet/sing-box/experimental/libbox"
	slmcore "github.com/slmtune/slmtune-ios/core"
)

func main() {
	fmt.Println(libbox.Version(), slmcore.Version())
}
