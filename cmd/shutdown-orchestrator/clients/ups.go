package clients

import (
  "bufio"
  "context"
  "fmt"
  "net"
  "strings"
  "sync"
  "time"
)

// NUTClient communicates with a NUT (Network UPS Tools) server over TCP.
// It maintains a persistent connection and reconnects automatically on error.
type NUTClient struct {
  host    string
  port    int
  upsName string

  mu      sync.Mutex
  conn    net.Conn
  scanner *bufio.Scanner
}

// NewNUTClient creates a new NUT client for the given server and UPS name.
func NewNUTClient(host string, port int, upsName string) *NUTClient {
  return &NUTClient{
    host:    host,
    port:    port,
    upsName: upsName,
  }
}

// GetStatus retrieves the ups.status variable from the NUT server.
// It reuses a persistent TCP connection, reconnecting on failure.
func (c *NUTClient) GetStatus(ctx context.Context) (string, error) {
  c.mu.Lock()
  defer c.mu.Unlock()

  // Try with existing connection first, then reconnect once on failure.
  if c.conn != nil {
    status, err := c.queryStatus(ctx)
    if err == nil {
      return status, nil
    }
    // Connection is stale or broken — close and reconnect.
    c.conn.Close()
    c.conn = nil
    c.scanner = nil
  }

  if err := c.connect(ctx); err != nil {
    return "", err
  }

  status, err := c.queryStatus(ctx)
  if err != nil {
    // Fresh connection failed — close it so next call retries.
    c.conn.Close()
    c.conn = nil
    c.scanner = nil
    return "", err
  }
  return status, nil
}

// Close closes the persistent connection if open.
func (c *NUTClient) Close() error {
  c.mu.Lock()
  defer c.mu.Unlock()
  if c.conn != nil {
    _, _ = c.conn.Write([]byte("LOGOUT\n"))
    err := c.conn.Close()
    c.conn = nil
    c.scanner = nil
    return err
  }
  return nil
}

// connect establishes a new TCP connection to the NUT server.
// Must be called with c.mu held.
func (c *NUTClient) connect(ctx context.Context) error {
  addr := fmt.Sprintf("%s:%d", c.host, c.port)
  var d net.Dialer
  conn, err := d.DialContext(ctx, "tcp", addr)
  if err != nil {
    return fmt.Errorf("connecting to NUT server at %s: %w", addr, err)
  }
  c.conn = conn
  c.scanner = bufio.NewScanner(conn)
  return nil
}

// queryStatus sends a GET VAR command and reads the response on the current connection.
// Must be called with c.mu held and c.conn != nil.
func (c *NUTClient) queryStatus(ctx context.Context) (string, error) {
  if deadline, ok := ctx.Deadline(); ok {
    c.conn.SetDeadline(deadline)
  } else {
    // Clear any previous deadline.
    c.conn.SetDeadline(time.Time{})
  }

  cmd := fmt.Sprintf("GET VAR %s ups.status\n", c.upsName)
  if _, err := c.conn.Write([]byte(cmd)); err != nil {
    return "", fmt.Errorf("sending GET VAR command: %w", err)
  }

  if !c.scanner.Scan() {
    if err := c.scanner.Err(); err != nil {
      return "", fmt.Errorf("reading NUT response: %w", err)
    }
    return "", fmt.Errorf("no response from NUT server")
  }

  return parseNUTVar(c.scanner.Text(), c.upsName, "ups.status")
}

// parseNUTVar extracts the value from a NUT protocol response line.
// Expected format: VAR <upsName> <varName> "<value>"
func parseNUTVar(line, upsName, varName string) (string, error) {
  prefix := fmt.Sprintf("VAR %s %s ", upsName, varName)
  if !strings.HasPrefix(line, prefix) {
    return "", fmt.Errorf("unexpected NUT response: %s", line)
  }

  value := strings.TrimPrefix(line, prefix)
  value = strings.Trim(value, "\"")
  return value, nil
}
