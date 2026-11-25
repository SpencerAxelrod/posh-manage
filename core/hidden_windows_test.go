package main

import (
	"os"
	"path/filepath"
	"slices"
	"syscall"
	"testing"
)

func TestC10WindowsHiddenThemes(t *testing.T) {
	directory := t.TempDir()
	files := []struct {
		name       string
		attributes uint32
	}{
		{name: "alpha.omp.json"},
		{name: "hidden.omp.json", attributes: syscall.FILE_ATTRIBUTE_HIDDEN},
		{name: "system.omp.json", attributes: syscall.FILE_ATTRIBUTE_SYSTEM},
		{name: "both.omp.json", attributes: syscall.FILE_ATTRIBUTE_HIDDEN | syscall.FILE_ATTRIBUTE_SYSTEM},
	}

	for _, file := range files {
		path := filepath.Join(directory, file.name)
		if err := os.WriteFile(path, []byte("{}"), 0o600); err != nil {
			t.Fatal(err)
		}
		if file.attributes == 0 {
			continue
		}

		nativePath, err := syscall.UTF16PtrFromString(path)
		if err != nil {
			t.Fatal(err)
		}
		if err := syscall.SetFileAttributes(nativePath, file.attributes); err != nil {
			t.Fatal(err)
		}
	}

	got, err := discoverThemes(directory)
	if err != nil {
		t.Fatal(err)
	}
	want := []Theme{
		{Name: "alpha.omp.json", Path: filepath.Join(directory, "alpha.omp.json")},
	}
	if !slices.Equal(got, want) {
		t.Fatalf("discoverThemes(%q) = %#v, want %#v", directory, got, want)
	}
}
