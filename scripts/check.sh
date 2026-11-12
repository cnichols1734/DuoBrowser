#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p work/checks
swiftc -warnings-as-errors DuoBrowser/ScrollChromeState.swift Tests/ScrollChromeStateTests.swift -o work/checks/scroll
work/checks/scroll
swiftc -warnings-as-errors DuoBrowser/BrowserData.swift DuoBrowser/TabArchive.swift Tests/TabArchiveTests.swift -o work/checks/archive
work/checks/archive
swiftc -warnings-as-errors DuoBrowser/BrowserData.swift DuoBrowser/TabArchive.swift Tests/BrowserDataTests.swift -o work/checks/data
work/checks/data
swiftc -warnings-as-errors DuoBrowser/BrowserData.swift DuoBrowser/TabArchive.swift DuoBrowser/AddressSuggestions.swift Tests/AddressSuggestionsTests.swift -o work/checks/suggestions
work/checks/suggestions
swiftc -warnings-as-errors DuoBrowser/BrowserData.swift DuoBrowser/TabArchive.swift DuoBrowser/BrowserImport.swift Tests/BrowserImportTests.swift -o work/checks/import
work/checks/import
swiftc -warnings-as-errors DuoBrowser/RedditLinks.swift Tests/RedditLinksTests.swift -o work/checks/reddit
work/checks/reddit
swiftc -warnings-as-errors DuoBrowser/FilterListConverter.swift Tests/FilterListConverterTests.swift -o work/checks/filters
work/checks/filters
swiftc -frontend -parse DuoBrowser/*.swift Tests/NativeBrowserChecks.swift
for source in DuoBrowser/*.js Tests/*.cjs; do node --check "$source"; done
python3 scripts/repository-check.py
git diff --check
