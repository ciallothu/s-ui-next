package logger

import (
	"fmt"
	"os"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/op/go-logging"
)

var (
	logger     *logging.Logger
	logBuffer  []bufferEntry
	logBufferM sync.RWMutex
)

type bufferEntry struct {
	timestamp int64
	time      string
	level     logging.Level
	log       string
	user      string
	source    string
}

// LogEntry is the structured representation used by the mobile API. The
// original string API remains available for backwards compatibility.
type LogEntry struct {
	Timestamp int64  `json:"timestamp"`
	Time      string `json:"time"`
	Level     string `json:"level"`
	Message   string `json:"message"`
	User      string `json:"user,omitempty"`
	Source    string `json:"source"`
}

type LogQuery struct {
	Level  string
	User   string
	Search string
	Start  int64
	End    int64
	Offset int
	Limit  int
}

func InitLogger(level logging.Level) {
	newLogger := logging.MustGetLogger("s-ui-next")
	var err error
	var backend logging.Backend
	var format logging.Formatter

	_, inContainer := os.LookupEnv("container")
	if !inContainer {
		if _, statErr := os.Stat("/.dockerenv"); statErr == nil {
			inContainer = true
		}
	}
	if inContainer {
		backend = logging.NewLogBackend(os.Stderr, "", 0)
		format = logging.MustStringFormatter(`%{time:2006/01/02 15:04:05} %{level} - %{message}`)
	} else {
		backend, err = logging.NewSyslogBackend("")
		if err != nil {
			fmt.Println("Unable to use syslog: " + err.Error())
			backend = logging.NewLogBackend(os.Stderr, "", 0)
		}
		if err != nil {
			format = logging.MustStringFormatter(`%{time:2006/01/02 15:04:05} %{level} - %{message}`)
		} else {
			format = logging.MustStringFormatter(`%{level} - %{message}`)
		}
	}

	backendFormatter := logging.NewBackendFormatter(backend, format)
	backendLeveled := logging.AddModuleLevel(backendFormatter)
	backendLeveled.SetLevel(level, "s-ui-next")
	newLogger.SetBackend(backendLeveled)

	logger = newLogger
}

func GetLogger() *logging.Logger {
	return logger
}

func Debug(args ...interface{}) {
	logger.Debug(args...)
	addToBuffer("DEBUG", fmt.Sprint(args...))
}

func Debugf(format string, args ...interface{}) {
	logger.Debugf(format, args...)
	addToBuffer("DEBUG", fmt.Sprintf(format, args...))
}

func Info(args ...interface{}) {
	logger.Info(args...)
	addToBuffer("INFO", fmt.Sprint(args...))
}

func Infof(format string, args ...interface{}) {
	logger.Infof(format, args...)
	addToBuffer("INFO", fmt.Sprintf(format, args...))
}

func Warning(args ...interface{}) {
	logger.Warning(args...)
	addToBuffer("WARNING", fmt.Sprint(args...))
}

func Warningf(format string, args ...interface{}) {
	logger.Warningf(format, args...)
	addToBuffer("WARNING", fmt.Sprintf(format, args...))
}

func Error(args ...interface{}) {
	logger.Error(args...)
	addToBuffer("ERROR", fmt.Sprint(args...))
}

func Errorf(format string, args ...interface{}) {
	logger.Errorf(format, args...)
	addToBuffer("ERROR", fmt.Sprintf(format, args...))
}

// Audit records an operator action with an explicit actor. Configuration
// changes are also persisted in the changes table; this is intended for
// actions such as restarts and imports that do not create a change row.
func Audit(user string, args ...interface{}) {
	message := fmt.Sprint(args...)
	logger.Info(message)
	addStructuredToBuffer("INFO", message, user, "audit")
}

func addToBuffer(level string, newLog string) {
	addStructuredToBuffer(level, newLog, "", "system")
}

func addStructuredToBuffer(level string, newLog string, user string, source string) {
	t := time.Now()
	logBufferM.Lock()
	defer logBufferM.Unlock()
	if len(logBuffer) >= 10240 {
		logBuffer = logBuffer[1:]
	}

	logLevel, _ := logging.LogLevel(level)
	logBuffer = append(logBuffer, bufferEntry{
		timestamp: t.Unix(),
		time:      t.Format("2006/01/02 15:04:05"),
		level:     logLevel,
		log:       newLog,
		user:      user,
		source:    source,
	})
}

func GetLogs(c int, level string) []string {
	if c <= 0 {
		c = 10
	}
	var output []string
	logLevel, _ := logging.LogLevel(level)

	logBufferM.RLock()
	defer logBufferM.RUnlock()
	for i := len(logBuffer) - 1; i >= 0 && len(output) < c; i-- {
		if logBuffer[i].level <= logLevel {
			output = append(output, fmt.Sprintf("%s %s - %s", logBuffer[i].time, logBuffer[i].level, logBuffer[i].log))
		}
	}
	return output
}

// QueryLogs filters the in-memory log ring without exposing its storage
// format. Results are newest-first and pagination is applied after filtering.
func QueryLogs(query LogQuery) ([]LogEntry, int) {
	if query.Offset < 0 {
		query.Offset = 0
	}
	if query.Limit <= 0 {
		query.Limit = 100
	}
	if query.Limit > 5000 {
		query.Limit = 5000
	}

	level := strings.ToUpper(strings.TrimSpace(query.Level))
	user := strings.ToLower(strings.TrimSpace(query.User))
	search := strings.ToLower(strings.TrimSpace(query.Search))

	logBufferM.RLock()
	entries := make([]LogEntry, 0, len(logBuffer))
	for _, entry := range logBuffer {
		levelName := entry.level.String()
		if level != "" && level != "ALL" && levelName != level {
			continue
		}
		if query.Start > 0 && entry.timestamp < query.Start {
			continue
		}
		if query.End > 0 && entry.timestamp > query.End {
			continue
		}
		if user != "" && !strings.Contains(strings.ToLower(entry.user), user) && !strings.Contains(strings.ToLower(entry.log), user) {
			continue
		}
		if search != "" && !strings.Contains(strings.ToLower(entry.log), search) && !strings.Contains(strings.ToLower(entry.user), search) {
			continue
		}
		entries = append(entries, LogEntry{
			Timestamp: entry.timestamp,
			Time:      entry.time,
			Level:     levelName,
			Message:   entry.log,
			User:      entry.user,
			Source:    entry.source,
		})
	}
	logBufferM.RUnlock()

	sort.Slice(entries, func(i, j int) bool { return entries[i].Timestamp > entries[j].Timestamp })
	total := len(entries)
	if query.Offset >= total {
		return []LogEntry{}, total
	}
	end := query.Offset + query.Limit
	if end > total {
		end = total
	}
	return entries[query.Offset:end], total
}
