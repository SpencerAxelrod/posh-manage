package main

import (
	"errors"
	"testing"
)

func TestCoreError(t *testing.T) {
	cause := errors.New("permission denied")
	tests := []struct {
		name  string
		cause error
		want  string
	}{
		{name: "without cause", want: "cannot read theme directory"},
		{name: "with cause", cause: cause, want: "cannot read theme directory: permission denied"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			var err error = &CoreError{
				Code:    "FILE_ACCESS_FAILED",
				Message: "cannot read theme directory",
				Cause:   test.cause,
			}

			if got := err.Error(); got != test.want {
				t.Errorf("Error() = %q, want %q", got, test.want)
			}
			if got := errors.Unwrap(err); got != test.cause {
				t.Errorf("Unwrap() = %v, want %v", got, test.cause)
			}
			if test.cause != nil && !errors.Is(err, test.cause) {
				t.Error("the original cause is no longer recognizable")
			}
		})
	}
}
