// Standalone (non-fuzzer) reproducer for the `configs-fuzzer` Mayhem target.
//
// Preserved from the original savantenvs/runc integration: it drives the exact code path
// the libFuzzer harness drives (libcontainer/configs FuzzUnmarshalJSON -> Hooks.UnmarshalJSON)
// but as a plain file-input program — one input, one run, a natural crash, no libFuzzer
// runtime. Use it to reproduce/triage a Mayhem finding:
//
//	/mayhem/configs_fuzzer_native <input-file>
//
// It is a repro artifact, not a Mayhem target (no Mayhemfile references it).
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
