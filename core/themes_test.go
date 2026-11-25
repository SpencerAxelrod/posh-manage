package main

import (
	"errors"
	"os"
	"path/filepath"
	"runtime"
	"slices"
	"testing"
)

func TestC01DiscoverThemes(t *testing.T) {
	directory := t.TempDir()
	for _, name := range []string{
		"beta.omp.json",
		"alpha.omp.json",
		"ignore.json",
		"ignore.omp.yaml",
	} {
		if err := os.WriteFile(filepath.Join(directory, name), []byte("not JSON"), 0o600); err != nil {
			t.Fatal(err)
		}
	}

	nestedDirectory := filepath.Join(directory, "nested.omp.json")
	if err := os.Mkdir(nestedDirectory, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(nestedDirectory, "nested.omp.json"), []byte("{}"), 0o600); err != nil {
		t.Fatal(err)
	}

	got, err := discoverThemes(directory)
	if err != nil {
		t.Fatal(err)
	}

	want := []Theme{
		{Name: "alpha.omp.json", Path: filepath.Join(directory, "alpha.omp.json")},
		{Name: "beta.omp.json", Path: filepath.Join(directory, "beta.omp.json")},
	}
	if !slices.Equal(got, want) {
		t.Fatalf("discoverThemes(%q) = %#v, want %#v", directory, got, want)
	}
}

func TestDiscoverThemesDirectoryErrors(t *testing.T) {
	directory := t.TempDir()
	filePath := filepath.Join(directory, "not-a-directory")
	if err := os.WriteFile(filePath, []byte("{}"), 0o600); err != nil {
		t.Fatal(err)
	}

	tests := []struct {
		name        string
		directory   string
		wantCode    string
		wantMissing bool
	}{
		{name: "C02 missing directory", directory: filepath.Join(directory, "missing"), wantCode: "THEME_DIRECTORY_MISSING", wantMissing: true},
		{name: "C02 empty directory", directory: t.TempDir(), wantCode: "THEME_DIRECTORY_EMPTY"},
		{name: "C02 file instead of directory", directory: filePath, wantCode: "FILE_ACCESS_FAILED"},
		{name: "C06 relative directory", directory: "relative", wantCode: "USAGE_ERROR"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			themes, err := discoverThemes(test.directory)
			if err == nil {
				t.Fatal("expected a directory error")
			}
			if themes != nil {
				t.Fatalf("expected no themes on failure, got %#v", themes)
			}

			var coreErr *CoreError
			if !errors.As(err, &coreErr) {
				t.Fatalf("expected a CoreError, got %T: %v", err, err)
			}
			if coreErr.Code != test.wantCode {
				t.Errorf("error code = %q, want %q", coreErr.Code, test.wantCode)
			}
			if test.wantMissing && !errors.Is(err, os.ErrNotExist) {
				t.Fatalf("expected a missing-path error, got %v", err)
			}
		})
	}
}

func TestC10DiscoverDotPrefixedTheme(t *testing.T) {
	directory := t.TempDir()
	for _, name := range []string{"alpha.omp.json", ".dot.omp.json"} {
		if err := os.WriteFile(filepath.Join(directory, name), []byte("{}"), 0o600); err != nil {
			t.Fatal(err)
		}
	}

	got, err := discoverThemes(directory)
	if err != nil {
		t.Fatal(err)
	}

	want := []Theme{}
	if runtime.GOOS == "windows" {
		want = append(want, Theme{
			Name: ".dot.omp.json",
			Path: filepath.Join(directory, ".dot.omp.json"),
		})
	}
	want = append(want, Theme{
		Name: "alpha.omp.json",
		Path: filepath.Join(directory, "alpha.omp.json"),
	})

	if !slices.Equal(got, want) {
		t.Fatalf("discoverThemes(%q) = %#v, want %#v", directory, got, want)
	}
}

func TestC10ThemeSuffix(t *testing.T) {
	windows := runtime.GOOS == "windows"
	tests := []struct {
		name     string
		filename string
		want     bool
	}{
		{name: "lowercase suffix", filename: "alpha.omp.json", want: true},
		{name: "uppercase suffix", filename: "alpha.OMP.JSON", want: windows},
		{name: "mixed case suffix", filename: "alpha.omp.JSON", want: windows},
		{name: "unrelated JSON", filename: "alpha.json", want: false},
		{name: "YAML theme", filename: "alpha.omp.yaml", want: false},
		{name: "extra extension", filename: "alpha.omp.json.bak", want: false},
		{name: "empty name", filename: "", want: false},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			got := hasThemeSuffix(test.filename)
			if got != test.want {
				t.Errorf("hasThemeSuffix(%q) = %t, want %t", test.filename, got, test.want)
			}
		})
	}
}
