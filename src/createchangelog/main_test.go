package main

import (
	"testing"
)

func TestChangeLogParser(t *testing.T) {
	commitText := `
Some text here

    [ChangeLog] Multi line text
	here

more text here
`

	entry := extractChangeLog(commitText)
	if entry.module != "" || entry.class != "" {
		t.Fatal("Unexpected groups parsed")
	}

	if entry.text != "Multi line text here" {
		t.Fatalf("Unexpected text extracted: %s", entry.text)
	}

	commitText = `
Some text here

    [ChangeLog][Some][Group] Multi line text
	here

more text here
`

	entry = extractChangeLog(commitText)
	if entry.module != "Some" && entry.class != "Group" {
		t.Fatalf("Groups incorrectly parsed: %s %s", entry.class, entry.module)
	}

	if entry.text != "Multi line text here" {
		t.Fatalf("Unexpected text extracted: %s", entry.text)
	}

}

func TestTaskExtraction(t *testing.T) {
	commitText := `
Some text here

    [ChangeLog] Blah

Task-Number: QTBUG-1234
`

	entry := extractChangeLog(commitText)

	if entry.text != "[QTBUG-1234] Blah" {
		t.Fatalf("Unexpected text extracted: %s", entry.text)
	}
}
