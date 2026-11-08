//go:build slm_bind

// Smoke test on a desktop: each extra core starts through the slmcore API and carries a request.
package main

import (
	"fmt"
	"net/http"
	"net/url"
	"os"
	"time"

	slmcore "github.com/slmtune/slmtune-ios/core"
)

type stdout struct{}

func (stdout) WriteLog(l string) { fmt.Println("  log:", l) }

func get(proxyPort int32) error {
	u, _ := url.Parse(fmt.Sprintf("socks5://127.0.0.1:%d", proxyPort))
	c := &http.Client{Timeout: 15 * time.Second, Transport: &http.Transport{Proxy: http.ProxyURL(u)}}
	r, err := c.Get("https://www.gstatic.com/generate_204")
	if err != nil {
		return err
	}
	r.Body.Close()
	if r.StatusCode != 204 {
		return fmt.Errorf("status %d", r.StatusCode)
	}
	return nil
}

func main() {
	slmcore.SetLogWriter(stdout{})
	fail := false
	p, _ := slmcore.FreePort()
	err := slmcore.StartXray("t", fmt.Sprintf(`{"inbounds":[{"listen":"127.0.0.1","port":%d,"protocol":"socks","settings":{"udp":true}}],"outbounds":[{"protocol":"freedom"}]}`, p))
	if err == nil {
		err = get(p)
	}
	fmt.Println("xray:", err)
	fail = fail || err != nil

	m, _ := slmcore.FreePort()
	dir, _ := os.MkdirTemp("", "mihomo")
	err = slmcore.StartMihomo(dir, fmt.Sprintf(`{"mode":"rule","log-level":"warning","proxies":[],"listeners":[{"name":"in0","type":"mixed","listen":"127.0.0.1","port":%d,"proxy":"DIRECT"}],"rules":["MATCH,DIRECT"]}`, m))
	if err == nil {
		time.Sleep(300 * time.Millisecond)
		err = get(int32(m))
	}
	fmt.Println("mihomo:", err)
	fail = fail || err != nil

	for _, t := range []string{"obfs4", "snowflake", "webtunnel", "meek_lite"} {
		port, err := slmcore.StartTransport(t, dir+"/pt")
		fmt.Println("transport", t, port, err)
		fail = fail || err != nil
	}
	slmcore.StopAll()
	fmt.Println("stopped; version:", slmcore.Version())
	if fail {
		os.Exit(1)
	}
}
