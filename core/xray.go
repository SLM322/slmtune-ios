package slmcore

import (
	"bytes"
	"fmt"
	"sync"

	"github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/infra/conf/serial"

	// Every Xray protocol and transport (VLESS, XHTTP, Reality, …).
	_ "github.com/xtls/xray-core/main/distro/all"
)

var (
	xrayMu        sync.Mutex
	xrayInstances = map[string]*core.Instance{}
)

func xrayVersion() string { return core.Version() }

// StartXray runs Xray with a JSON config (SOCKS inbound on 127.0.0.1 → the server) under an id
// (one per server of the connection: a cascade or a group may need several).
func StartXray(id string, configJSON string) error {
	cfg, err := serial.LoadJSONConfig(bytes.NewReader([]byte(configJSON)))
	if err != nil {
		return fmt.Errorf("xray config: %w", err)
	}
	inst, err := core.New(cfg)
	if err != nil {
		return fmt.Errorf("xray: %w", err)
	}
	if err := inst.Start(); err != nil {
		_ = inst.Close()
		return fmt.Errorf("xray start: %w", err)
	}
	xrayMu.Lock()
	if old := xrayInstances[id]; old != nil {
		_ = old.Close()
	}
	xrayInstances[id] = inst
	xrayMu.Unlock()
	logf("xray %s started", id)
	return nil
}

// StopXray stops one Xray instance.
func StopXray(id string) {
	xrayMu.Lock()
	inst := xrayInstances[id]
	delete(xrayInstances, id)
	xrayMu.Unlock()
	if inst != nil {
		_ = inst.Close()
	}
}

// StopAllXray stops every Xray instance.
func StopAllXray() {
	xrayMu.Lock()
	list := xrayInstances
	xrayInstances = map[string]*core.Instance{}
	xrayMu.Unlock()
	for _, inst := range list {
		_ = inst.Close()
	}
}
