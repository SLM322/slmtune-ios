package slmcore

import (
	"fmt"
	"io"
	"net"
	"os"
	"sync"

	"gitlab.torproject.org/tpo/anti-censorship/pluggable-transports/lyrebird/common/socks5"
	"gitlab.torproject.org/tpo/anti-censorship/pluggable-transports/lyrebird/transports"
	"gitlab.torproject.org/tpo/anti-censorship/pluggable-transports/lyrebird/transports/base"
	"golang.org/x/net/proxy"
)

// Tor's pluggable transports (obfs4, meek_lite, webtunnel, snowflake) in-process: iOS cannot run lyrebird as
// a separate program, so this is lyrebird's client loop as a library. Tor (Tor.framework in the extension)
// is configured with "ClientTransportPlugin <name> socks5 127.0.0.1:<port>" pointing at these listeners.

var (
	ptMu        sync.Mutex
	ptInit      sync.Once
	ptInitErr   error
	ptListeners = map[string]net.Listener{}
)

// StartTransport starts one transport's SOCKS5 listener and returns its port.
func StartTransport(name string, stateDir string) (int32, error) {
	ptInit.Do(func() { ptInitErr = transports.Init() })
	if ptInitErr != nil {
		return 0, ptInitErr
	}
	t := transports.Get(name)
	if t == nil {
		return 0, fmt.Errorf("no such transport: %s", name)
	}
	if err := os.MkdirAll(stateDir, 0o700); err != nil {
		return 0, err
	}
	f, err := t.ClientFactory(stateDir)
	if err != nil {
		return 0, err
	}
	f.OnEvent(func(e base.TransportEvent) { logf("%s: %s", name, e.String()) })
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return 0, err
	}
	ptMu.Lock()
	if old := ptListeners[name]; old != nil {
		_ = old.Close()
	}
	ptListeners[name] = ln
	ptMu.Unlock()
	go acceptLoop(f, ln)
	return int32(ln.Addr().(*net.TCPAddr).Port), nil
}

// StopTransports closes every transport listener.
func StopTransports() {
	ptMu.Lock()
	list := ptListeners
	ptListeners = map[string]net.Listener{}
	ptMu.Unlock()
	for _, ln := range list {
		_ = ln.Close()
	}
}

func acceptLoop(f base.ClientFactory, ln net.Listener) {
	for {
		conn, err := ln.Accept()
		if err != nil {
			return
		}
		go handle(f, conn)
	}
}

func handle(f base.ClientFactory, conn net.Conn) {
	defer conn.Close()
	name := f.Transport().Name()
	req, err := socks5.Handshake(conn)
	if err != nil {
		logf("%s: socks handshake: %v", name, err)
		return
	}
	args, err := f.ParseArgs(&req.Args)
	if err != nil {
		logf("%s: bad bridge arguments: %v", name, err)
		_ = req.Reply(socks5.ReplyGeneralFailure)
		return
	}
	remote, err := f.Dial("tcp", req.Target, proxy.Direct.Dial, args)
	if err != nil {
		logf("%s: connect failed: %v", name, err)
		_ = req.Reply(socks5.ErrorToReplyCode(err))
		return
	}
	defer remote.Close()
	if err := req.Reply(socks5.ReplySucceeded); err != nil {
		return
	}
	done := make(chan struct{}, 2)
	go func() { _, _ = io.Copy(remote, conn); done <- struct{}{} }()
	go func() { _, _ = io.Copy(conn, remote); done <- struct{}{} }()
	<-done
}
