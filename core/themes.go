package main

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

type Theme struct {
	Name string `json:"name"`
	Path string `json:"path"`
}

func discoverThemes(directory string) ([]Theme, error) {
	if !filepath.IsAbs(directory) {
		return nil, &CoreError{
			Code:    "USAGE_ERROR",
			Message: fmt.Sprintf("theme directory must be absolute: %q", directory),
		}
	}

	info, err := os.Stat(directory)
	if err != nil {
		return nil, directoryAccessError(directory, err)
	}
	if !info.IsDir() {
		return nil, &CoreError{
			Code:    "FILE_ACCESS_FAILED",
			Message: fmt.Sprintf("theme directory path is not a directory: %q", directory),
		}
	}

	entries, err := os.ReadDir(directory)
	if err != nil {
		return nil, directoryAccessError(directory, err)
	}

	themes := make([]Theme, 0)
	for _, entry := range entries {
		if entry.IsDir() || !hasThemeSuffix(entry.Name()) {
			continue
		}

		path := filepath.Join(directory, entry.Name())
		hidden, err := isHiddenTheme(entry)
		if err != nil {
			return nil, &CoreError{
				Code:    "FILE_ACCESS_FAILED",
				Message: fmt.Sprintf("inspect theme file %q", path),
				Cause:   err,
			}
		}
		if hidden {
			continue
		}

		themes = append(themes, Theme{
			Name: entry.Name(),
			Path: path,
		})
	}

	if len(themes) == 0 {
		return nil, &CoreError{
			Code:    "THEME_DIRECTORY_EMPTY",
			Message: fmt.Sprintf("no theme files found in %q", directory),
		}
	}

	return themes, nil
}

func directoryAccessError(directory string, cause error) *CoreError {
	code := "FILE_ACCESS_FAILED"
	if errors.Is(cause, os.ErrNotExist) {
		code = "THEME_DIRECTORY_MISSING"
	}

	return &CoreError{
		Code:    code,
		Message: fmt.Sprintf("access theme directory %q", directory),
		Cause:   cause,
	}
}

func hasThemeSuffix(name string) bool {
	if runtime.GOOS == "windows" {
		name = strings.ToLower(name)
	}

	return strings.HasSuffix(name, ".omp.json")
}
