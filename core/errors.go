package main

type CoreError struct {
	Code    string
	Message string
	Cause   error
}

func (e *CoreError) Error() string {
	if e.Cause != nil {
		return e.Message + ": " + e.Cause.Error()
	}

	return e.Message
}

func (e *CoreError) Unwrap() error {
	return e.Cause
}
