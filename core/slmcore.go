// Package slmcore holds the extra cores of SLMtune for iOS, built into the same gomobile framework as
// sing-box's libbox (two Go runtimes cannot live in one process): Xray, mihomo and Tor's pluggable transports.
// Each core listens on a local SOCKS port; sing-box in the Packet Tunnel routes to it with a socks outbound —
// the same scheme as the Windows version, only in one process instead of separate executables.
//
// Build: scripts/build-libbox.sh (gomobile bind of libbox + this package).
package slmcore

import (
	"fmt"
	"net"
	"sync"
)

// FreePort returns a free TCP port on 127.0.0.1 for a backend core.
func FreePort() (int32, error) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return 0, err
	}
	defer ln.Close()
	return int32(ln.Addr().(*net.TCPAddr).Port), nil
}

// StopAll stops every extra core (on tunnel stop).
func StopAll() {
	StopAllXray()
	StopMihomo()
	StopTransports()
}

// Version names the bundled cores, for the About screen.
func Version() string {
	return fmt.Sprintf("Xray %s · mihomo %s · lyrebird", xrayVersion(), mihomoVersion())
}

var (
	logMu   sync.Mutex
	logSink LogWriter
)

// LogWriter receives the cores' log lines (the extension appends them to the shared log file).
type LogWriter interface {
	WriteLog(line string)
}

// SetLogWriter sets where the cores' logs go (nil = discard).
func SetLogWriter(w LogWriter) {
	logMu.Lock()
	logSink = w
	logMu.Unlock()
}

func logf(format string, args ...any) {
	logMu.Lock()
	w := logSink
	logMu.Unlock()
	if w != nil {
		w.WriteLog(fmt.Sprintf(format, args...))
	}
}
