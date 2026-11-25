//go:build !windows

package main

import (
	"os"
	"strings"
)

func isHiddenTheme(entry os.DirEntry) (bool, error) {
	return strings.HasPrefix(entry.Name(), "."), nil
}
