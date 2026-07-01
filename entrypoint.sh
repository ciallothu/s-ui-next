#!/bin/sh

DB_FOLDER="${SUI_DB_FOLDER:-/app/db}"
DB_PATH="${DB_FOLDER}/s-ui-next.db"
if [ ! -f "$DB_PATH" ] && [ -f "${DB_FOLDER}/s-ui.db" ]; then
	DB_PATH="${DB_FOLDER}/s-ui.db"
fi
if [ -f "$DB_PATH" ]; then
	./sui migrate
fi

exec ./sui
