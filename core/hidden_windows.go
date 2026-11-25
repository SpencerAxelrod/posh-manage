package main

import (
	"fmt"
	"os"
	"syscall"
)

func isHiddenTheme(entry os.DirEntry) (bool, error) {
	info, err := entry.Info()
	if err != nil {
		return false, err
	}

	attributes, ok := info.Sys().(*syscall.Win32FileAttributeData)
	if !ok || attributes == nil {
		return false, fmt.Errorf("Windows file attributes are unavailable for %q", entry.Name())
	}

	const hiddenMask = syscall.FILE_ATTRIBUTE_HIDDEN | syscall.FILE_ATTRIBUTE_SYSTEM
	return attributes.FileAttributes&hiddenMask != 0, nil
}
