package main

import (
  "fmt"
  "log"
  "os"
)

func main() {
  cfg := LoadConfig()
  if err := cfg.Validate(); err != nil {
    log.Fatalf("invalid configuration: %v", err)
  }

  switch cfg.Mode {
  case "monitor":
    fmt.Println("monitor mode not yet implemented")
    os.Exit(1)
  case "test":
    fmt.Println("test mode not yet implemented")
    os.Exit(1)
  case "preflight":
    fmt.Println("preflight mode not yet implemented")
    os.Exit(1)
  }
}
