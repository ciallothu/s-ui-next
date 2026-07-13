package migration

import (
	"testing"

	"gorm.io/gorm"
)

func TestRunMigrationStepConvertsPanicToError(t *testing.T) {
	err := runMigrationStep("test", nil, func(*gorm.DB) error {
		panic("broken database")
	})
	if err == nil {
		t.Fatal("migration panic should be returned as an error")
	}
}

func TestVersionSeriesRequiresSegmentBoundary(t *testing.T) {
	if !isVersionSeries("1.1.9", "1.1") {
		t.Fatal("patch release should match its version series")
	}
	if isVersionSeries("1.10.0", "1.1") {
		t.Fatal("1.10 must not be treated as the 1.1 series")
	}
}
