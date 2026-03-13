#!/bin/bash

SHELL_BIN="stack exec my-shell --"
PASS=0
FAIL=0

run_test() {
    local desc="$1"
    local input="$2"
    local expected="$3"
    local actual=$(echo -e "$input" | stack exec my-shell 2>/dev/null | tr -d '\r')
    if echo "$actual" | grep -q "$expected"; then
        echo "✓ $desc"
        ((PASS++))
    else
        echo "✗ $desc"
        echo "  Expected: $expected"
        echo "  Got:      $actual"
        ((FAIL++))
    fi
}

echo "================================"
echo "   my-shell Test Suite"
echo "================================"

run_test "echo single word"     "echo hello"              "hello"
run_test "echo multiple words"  "echo hello world"        "hello world"
run_test "pwd"                  "pwd"                     "$(pwd)"
run_test "type echo"            "type echo"               "echo is a shell builtin"
run_test "type exit"            "type exit"               "exit is a shell builtin"
run_test "type cat"             "type cat"                "cat is /bin/cat"
run_test "invalid command"      "invalidcmd"              "invalidcmd: command not found"
run_test "cd to /tmp"           "cd /tmp\npwd"            "/tmp"
run_test "cd invalid dir"       "cd /nonexistent"         "No such file or directory"
run_test "stdout redirect"      "echo hi > /tmp/t.txt\ncat /tmp/t.txt" "hi"
run_test "append redirect"      "echo a > /tmp/t.txt\necho b >> /tmp/t.txt\ncat /tmp/t.txt" "b"
run_test "single quotes"        "echo 'hello world'"      "hello world"
run_test "double quotes"        'echo "hello world"'      "hello world"
run_test "exit"                 "exit 0"                  ""

echo "================================"
echo "  Passed: $PASS | Failed: $FAIL"
echo "================================"