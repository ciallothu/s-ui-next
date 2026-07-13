package database

import (
	"os"
	"path/filepath"
	"testing"

	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

func TestValidateSQLiteDatabase(t *testing.T) {
	validPath := filepath.Join(t.TempDir(), "valid.db")
	db, err := gorm.Open(sqlite.Open(validPath), &gorm.Config{})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.Exec("CREATE TABLE settings (id integer primary key, key text, value text)").Error; err != nil {
		t.Fatal(err)
	}
	sqlDB, err := db.DB()
	if err != nil {
		t.Fatal(err)
	}
	if err := sqlDB.Close(); err != nil {
		t.Fatal(err)
	}
	if err := validateSQLiteDatabase(validPath); err != nil {
		t.Fatalf("valid database rejected: %v", err)
	}

	invalidPath := filepath.Join(t.TempDir(), "invalid.db")
	if err := os.WriteFile(invalidPath, []byte("SQLite format 3\x00not-a-database"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := validateSQLiteDatabase(invalidPath); err == nil {
		t.Fatal("corrupt database should be rejected")
	}
}
