package main

import (
	"os"

	"github.com/opencontainers/runc/libcontainer/configs"
)

func main() {
	if len(os.Args) < 2 {
		return
	}
	data, err := os.ReadFile(os.Args[1])
	if err != nil {
		return
	}
	hooks := configs.Hooks{}
	_ = hooks.UnmarshalJSON(data)
}
