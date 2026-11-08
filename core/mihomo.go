package slmcore

import (
	"fmt"
	"sync"

	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub/executor"
)

var (
	mihomoMu      sync.Mutex
	mihomoRunning bool
)

func mihomoVersion() string { return C.Version }

// StartMihomo applies a mihomo config (JSON is valid YAML): one proxy per server that needs mihomo
// (AmneziaWG, mieru, ShadowsocksR), each behind its own mixed listener on 127.0.0.1.
// mihomo is a process-wide singleton, so every such server of the connection goes into this one config.
func StartMihomo(homeDir string, configYAML string) error {
	mihomoMu.Lock()
	defer mihomoMu.Unlock()
	C.SetHomeDir(homeDir)
	cfg, err := config.Parse([]byte(configYAML))
	if err != nil {
		return fmt.Errorf("mihomo config: %w", err)
	}
	executor.ApplyConfig(cfg, true)
	mihomoRunning = true
	logf("mihomo started")
	return nil
}

// StopMihomo closes mihomo's listeners.
func StopMihomo() {
	mihomoMu.Lock()
	defer mihomoMu.Unlock()
	if !mihomoRunning {
		return
	}
	// An empty config drops the proxies (WireGuard sessions included), Shutdown closes the listeners.
	if cfg, err := config.Parse([]byte("mode: direct\nproxies: []\nrules: []\n")); err == nil {
		executor.ApplyConfig(cfg, true)
	}
	executor.Shutdown()
	mihomoRunning = false
}
