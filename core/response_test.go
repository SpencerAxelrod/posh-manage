package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"testing"
	"unicode/utf8"
)

func TestC09ThemeListSuccessJSON(t *testing.T) {
	directory := t.TempDir()
	name := "caf\u00e9 [literal $HOME].omp.json"
	path := filepath.Join(directory, name)
	if err := os.WriteFile(path, []byte("not JSON"), 0o600); err != nil {
		t.Fatal(err)
	}

	got := decodeResponseJSON(t, listThemesResponse(directory))
	want := map[string]any{
		"protocol_version": float64(1),
		"command":          "themes.list",
		"ok":               true,
		"data": map[string]any{
			"directory": directory,
			"themes": []any{
				map[string]any{"name": name, "path": path},
			},
			"total": float64(1),
		},
		"error": nil,
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("response = %#v, want %#v", got, want)
	}
}

func TestC09ThemeListFailureJSON(t *testing.T) {
	directory := filepath.Join(t.TempDir(), "missing")
	got := decodeResponseJSON(t, listThemesResponse(directory))

	if got["protocol_version"] != float64(1) || got["command"] != "themes.list" {
		t.Fatalf("unexpected response metadata: %#v", got)
	}
	if got["ok"] != false || got["data"] != nil {
		t.Fatalf("failure must have ok: false and data: null, got %#v", got)
	}

	failure, ok := got["error"].(map[string]any)
	if !ok {
		t.Fatalf("expected an error object, got %#v", got["error"])
	}
	if failure["code"] != "THEME_DIRECTORY_MISSING" {
		t.Errorf("error code = %v, want THEME_DIRECTORY_MISSING", failure["code"])
	}
	if message, ok := failure["message"].(string); !ok || message == "" {
		t.Errorf("expected a nonempty error message, got %#v", failure["message"])
	}

	details, ok := failure["details"].(map[string]any)
	if !ok {
		t.Fatalf("expected a details object, got %#v", failure["details"])
	}
	if details["directory"] != directory {
		t.Errorf("error directory = %v, want %q", details["directory"], directory)
	}
	if cause, ok := details["cause"].(string); !ok || cause == "" {
		t.Errorf("expected the original diagnostic, got %#v", details["cause"])
	}
}

func TestC09UnrecognizedCommandJSON(t *testing.T) {
	response := Response{
		ProtocolVersion: protocolVersion,
		Error: &ResponseError{
			Code:    "USAGE_ERROR",
			Message: "Unknown command.",
			Details: map[string]string{},
		},
	}

	got := decodeResponseJSON(t, response)
	want := map[string]any{
		"protocol_version": float64(1),
		"command":          nil,
		"ok":               false,
		"data":             nil,
		"error": map[string]any{
			"code":    "USAGE_ERROR",
			"message": "Unknown command.",
			"details": map[string]any{},
		},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("response = %#v, want %#v", got, want)
	}
}

func TestWriteResponseFailure(t *testing.T) {
	cause := errors.New("output is closed")
	err := writeResponse(failingWriter{cause: cause}, Response{})
	if !errors.Is(err, cause) {
		t.Fatalf("writeResponse() error = %v, want %v", err, cause)
	}
}

type failingWriter struct {
	cause error
}

func (w failingWriter) Write(data []byte) (int, error) {
	return 0, w.cause
}

func decodeResponseJSON(t *testing.T, response Response) map[string]any {
	t.Helper()
	var output bytes.Buffer
	if err := writeResponse(&output, response); err != nil {
		t.Fatal(err)
	}

	raw := output.Bytes()
	if !bytes.HasSuffix(raw, []byte("\n")) {
		t.Error("response must end with a newline")
	}
	if bytes.HasPrefix(raw, []byte{0xef, 0xbb, 0xbf}) {
		t.Error("response must not start with a byte-order mark")
	}
	if !utf8.Valid(raw) {
		t.Error("response must contain valid UTF-8")
	}

	var got map[string]any
	if err := json.Unmarshal(raw, &got); err != nil {
		t.Fatalf("expected exactly one JSON object, got %q: %v", raw, err)
	}
	for _, field := range []string{"protocol_version", "command", "ok", "data", "error"} {
		if _, exists := got[field]; !exists {
			t.Errorf("required response field %q is missing", field)
		}
	}
	return got
}
