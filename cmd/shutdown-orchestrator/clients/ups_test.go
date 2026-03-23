package clients

import (
  "context"
  "fmt"
  "net"
  "strings"
  "testing"
)

// fakeNUTServer starts a TCP listener that responds to NUT protocol GET VAR commands.
// It handles multiple commands per connection to test persistent connection reuse.
func fakeNUTServer(t *testing.T, upsName, statusValue string) (string, int, func()) {
  t.Helper()

  ln, err := net.Listen("tcp", "127.0.0.1:0")
  if err != nil {
    t.Fatalf("failed to start fake NUT server: %v", err)
  }

  addr := ln.Addr().(*net.TCPAddr)

  go func() {
    for {
      conn, err := ln.Accept()
      if err != nil {
        return // listener closed
      }
      go func(c net.Conn) {
        defer c.Close()
        buf := make([]byte, 1024)
        for {
          n, err := c.Read(buf)
          if err != nil {
            return
          }
          line := strings.TrimSpace(string(buf[:n]))
          if line == "LOGOUT" {
            return
          }
          expected := fmt.Sprintf("GET VAR %s ups.status", upsName)
          if line == expected {
            resp := fmt.Sprintf("VAR %s ups.status \"%s\"\n", upsName, statusValue)
            c.Write([]byte(resp))
          } else {
            c.Write([]byte("ERR UNKNOWN\n"))
          }
        }
      }(conn)
    }
  }()

  return addr.IP.String(), addr.Port, func() { ln.Close() }
}

func TestNUTClientGetStatus(t *testing.T) {
  host, port, cleanup := fakeNUTServer(t, "ups1", "OL")
  defer cleanup()

  client := NewNUTClient(host, port, "ups1")
  defer client.Close()

  status, err := client.GetStatus(context.Background())
  if err != nil {
    t.Fatalf("unexpected error: %v", err)
  }
  if status != "OL" {
    t.Errorf("expected status %q, got %q", "OL", status)
  }
}

func TestNUTClientGetStatusOnBattery(t *testing.T) {
  host, port, cleanup := fakeNUTServer(t, "ups1", "OB DISCHRG")
  defer cleanup()

  client := NewNUTClient(host, port, "ups1")
  defer client.Close()

  status, err := client.GetStatus(context.Background())
  if err != nil {
    t.Fatalf("unexpected error: %v", err)
  }
  if !strings.Contains(status, "OB") {
    t.Errorf("expected status to contain %q, got %q", "OB", status)
  }
}

func TestNUTClientConnectionRefused(t *testing.T) {
  client := NewNUTClient("127.0.0.1", 1, "ups1")
  defer client.Close()

  _, err := client.GetStatus(context.Background())
  if err == nil {
    t.Fatal("expected error for connection refused, got nil")
  }
}

func TestNUTClientReusesConnection(t *testing.T) {
  host, port, cleanup := fakeNUTServer(t, "ups1", "OL")
  defer cleanup()

  client := NewNUTClient(host, port, "ups1")
  defer client.Close()

  // First call establishes connection.
  status, err := client.GetStatus(context.Background())
  if err != nil {
    t.Fatalf("first call: unexpected error: %v", err)
  }
  if status != "OL" {
    t.Errorf("first call: expected %q, got %q", "OL", status)
  }

  // Second call reuses the same connection.
  status, err = client.GetStatus(context.Background())
  if err != nil {
    t.Fatalf("second call: unexpected error: %v", err)
  }
  if status != "OL" {
    t.Errorf("second call: expected %q, got %q", "OL", status)
  }
}

func TestNUTClientReconnectsAfterClose(t *testing.T) {
  host, port, cleanup := fakeNUTServer(t, "ups1", "OL")
  defer cleanup()

  client := NewNUTClient(host, port, "ups1")
  defer client.Close()

  // Establish connection.
  status, err := client.GetStatus(context.Background())
  if err != nil {
    t.Fatalf("first call: unexpected error: %v", err)
  }
  if status != "OL" {
    t.Errorf("first call: expected %q, got %q", "OL", status)
  }

  // Force-close the persistent connection to simulate a network failure.
  client.Close()

  // Next call should reconnect transparently.
  status, err = client.GetStatus(context.Background())
  if err != nil {
    t.Fatalf("reconnect call: unexpected error: %v", err)
  }
  if status != "OL" {
    t.Errorf("reconnect call: expected %q, got %q", "OL", status)
  }
}
