# 🧪 Test Architecture — Baton Orchestrator

## Overview

This repository uses a lightweight, POSIX-compliant shell-based testing framework to validate critical scripts and infrastructure logic.  
The goal is to maintain **clarity**, **portability**, and **early failure detection** without introducing external dependencies.

---

## 🧱 Structure

```
/tests
  run-tests.sh          # Test runner (executes all test scripts)
  test_*.sh             # Top-level test cases
  /unit/                # Unit-level logic and file tests
  /integration/         # Cross-component or env-related tests
```

Each test file:

- Is a standalone `.sh` script
- Uses `exit 0` for success and `exit 1` for failure
- Must be executable (`chmod +x`)
- Must have a `.sh` extension to be discovered automatically

---

## ✅ How It Works

The `run-tests.sh` script:

- Recursively discovers all `.sh` test files in `/tests` and its subfolders  
- Skips itself to avoid recursion  
- Runs each script using `sh <script>`  
- Tracks and reports:
  - ✅ Passed tests  
  - ❌ Failed tests  
  - 📊 Total test count  

It prints a detailed summary at the end and exits with code `1` if **any test fails**,  
making it directly usable in CI/CD workflows.

---

## 🧪 Writing a Test

Example test script:

```sh
#!/bin/sh
set -eu

echo "[test_name] Description..."

if [ <some condition> ]; then
  echo "[test_name] ✅ Passed"
  exit 0
else
  echo "[test_name] ❌ Failed"
  exit 1
fi
```

Each test should be **self-contained**, easy to read, and return a clear success or failure state.

---

## 🛠 Test Categories

| Folder               | Purpose                                                                 |
|-----------------------|--------------------------------------------------------------------------|
| `/tests/unit/`        | Validate individual script behavior, variable setting, and argument parsing |
| `/tests/integration/` | Validate orchestration, environment setup, and Docker-based workflows      |
| `/tests/`             | General or meta-tests, sanity checks, and critical path validations        |

---

## 🧾 Developer Guidelines

- ✅ Add tests when introducing or modifying scripts  
- ✅ Keep tests **short**, **isolated**, and **readable**  
- ❌ Don’t assume `$PWD` — use relative paths with `BASE_DIR` if needed  
- 🔁 Reuse shared test logic where possible  
- 🧪 Validate real-world behavior (outputs, exit codes, file existence)

---

## 📋 Example Usage

Run all tests from anywhere in the repo:

```bash
./tests/run-tests.sh
```

Expected output example:

```
🔍 Running all test scripts in ./tests (recursively)
▶️  Running: ./tests/test_sanity_check.sh
[test_sanity_check] Checking that 1 + 1 equals 2...
✅ ./tests/test_sanity_check.sh PASSED

📊 Total tests run: 1
✅ Passed: 1
❌ Failed: 0
🎉 All tests passed!
```

---

> **Note:**  
> This lightweight shell-based approach is intentionally minimal — it integrates seamlessly with CI/CD,  
> runs on any POSIX environment, and avoids heavy dependencies or external frameworks.