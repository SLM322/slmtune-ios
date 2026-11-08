//go:build slm_bind

package slmcore

// Keeps libbox and SagerNet's gomobile in this module's build list, so `gomobile bind` can put
// libbox and slmcore into one framework (scripts/build-libbox.sh).
import (
	_ "github.com/sagernet/gomobile"
	_ "github.com/sagernet/sing-box/experimental/libbox"
)
