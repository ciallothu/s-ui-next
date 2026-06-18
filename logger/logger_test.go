package logger

import "testing"

func TestQueryLogsIncludesEveryStructuredLevel(t *testing.T) {
	logBufferM.Lock()
	previous := logBuffer
	logBuffer = nil
	logBufferM.Unlock()
	t.Cleanup(func() {
		logBufferM.Lock()
		logBuffer = previous
		logBufferM.Unlock()
	})

	addStructuredToBuffer("DEBUG", "debug-entry", "", "system")
	addStructuredToBuffer("INFO", "info-entry", "alice", "audit")
	addStructuredToBuffer("WARNING", "warning-entry", "", "system")
	addStructuredToBuffer("ERROR", "error-entry", "", "system")

	for _, level := range []string{"DEBUG", "INFO", "WARNING", "ERROR"} {
		entries, total := QueryLogs(LogQuery{Level: level, Limit: 10})
		if total != 1 || len(entries) != 1 || entries[0].Level != level {
			t.Fatalf("level %s was not returned exactly once: total=%d entries=%#v", level, total, entries)
		}
	}
}
