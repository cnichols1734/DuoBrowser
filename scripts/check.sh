#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p work/checks
swiftc -warnings-as-errors DuoBrowser/ScrollChromeState.swift Tests/ScrollChromeStateTests.swift -o work/checks/scroll
work/checks/scroll
swiftc -warnings-as-errors DuoBrowser/TabArchive.swift Tests/TabArchiveTests.swift -o work/checks/archive
work/checks/archive
swiftc -warnings-as-errors DuoBrowser/BrowserData.swift DuoBrowser/TabArchive.swift Tests/BrowserDataTests.swift -o work/checks/data
work/checks/data
swiftc -warnings-as-errors DuoBrowser/BrowserData.swift DuoBrowser/TabArchive.swift DuoBrowser/AddressSuggestions.swift Tests/AddressSuggestionsTests.swift -o work/checks/suggestions
work/checks/suggestions
python3 Tests/make_bookmark_fixtures.py
swiftc -warnings-as-errors DuoBrowser/BrowserData.swift DuoBrowser/TabArchive.swift DuoBrowser/SafariBookmarkImport.swift Tests/SafariBookmarkImportTests.swift -o work/checks/import
work/checks/import
swiftc -frontend -parse DuoBrowser/*.swift Tests/NativeBrowserChecks.swift
for source in DuoBrowser/*.js Tests/*.cjs; do node --check "$source"; done
python3 scripts/repository-check.py
git diff --check
