package clients

import (
  "bufio"
  "context"
  "fmt"
  "net"
  "strings"
)

// NUTClient communicates with a NUT (Network UPS Tools) server over TCP.
type NUTClient struct {
  host    string
  port    int
  upsName string
}

// NewNUTClient creates a new NUT client for the given server and UPS name.
func NewNUTClient(host string, port int, upsName string) *NUTClient {
  return &NUTClient{
    host:    host,
    port:    port,
    upsName: upsName,
  }
}

// GetStatus connects to the NUT server and retrieves the ups.status variable.
func (c *NUTClient) GetStatus(ctx context.Context) (string, error) {
  addr := fmt.Sprintf("%s:%d", c.host, c.port)

  var d net.Dialer
  conn, err := d.DialContext(ctx, "tcp", addr)
  if err != nil {
    return "", fmt.Errorf("connecting to NUT server at %s: %w", addr, err)
  }
  defer conn.Close()

  cmd := fmt.Sprintf("GET VAR %s ups.status\n", c.upsName)
  if _, err := conn.Write([]byte(cmd)); err != nil {
    return "", fmt.Errorf("sending GET VAR command: %w", err)
  }

  scanner := bufio.NewScanner(conn)
  if !scanner.Scan() {
    if err := scanner.Err(); err != nil {
      return "", fmt.Errorf("reading NUT response: %w", err)
    }
    return "", fmt.Errorf("no response from NUT server")
  }

  line := scanner.Text()
  return parseNUTVar(line, c.upsName, "ups.status")
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
