package main

import (
	"encoding/json"
	"errors"
	"io"
)

const protocolVersion = 1

type Response struct {
	ProtocolVersion int            `json:"protocol_version"`
	Command         *string        `json:"command"`
	OK              bool           `json:"ok"`
	Data            any            `json:"data"`
	Error           *ResponseError `json:"error"`
}

type ResponseError struct {
	Code    string            `json:"code"`
	Message string            `json:"message"`
	Details map[string]string `json:"details"`
}

type ThemeListData struct {
	Directory string  `json:"directory"`
	Themes    []Theme `json:"themes"`
	Total     int     `json:"total"`
}

func listThemesResponse(directory string) Response {
	command := "themes.list"
	response := Response{
		ProtocolVersion: protocolVersion,
		Command:         &command,
	}

	themes, err := discoverThemes(directory)
	if err != nil {
		failure := &ResponseError{
			Code:    "INTERNAL_ERROR",
			Message: "Theme discovery failed.",
			Details: map[string]string{"directory": directory},
		}

		var coreErr *CoreError
		if errors.As(err, &coreErr) {
			failure.Code = coreErr.Code
			failure.Message = coreErr.Message
			if coreErr.Cause != nil {
				failure.Details["cause"] = coreErr.Cause.Error()
			}
		} else {
			failure.Details["cause"] = err.Error()
		}

		response.Error = failure
		return response
	}

	response.OK = true
	response.Data = ThemeListData{
		Directory: directory,
		Themes:    themes,
		Total:     len(themes),
	}
	return response
}

func writeResponse(output io.Writer, response Response) error {
	return json.NewEncoder(output).Encode(response)
}
