#!/usr/bin/env bats
# Tests for server-healthcheck. External commands are mocked via PATH.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HC="$ROOT/bin/server-healthcheck"
  FIX="$ROOT/tests/fixtures"
  export PATH="$ROOT/tests/mocks:$PATH"
  export HC_PROC_LOADAVG="$FIX/loadavg_low" HC_PROC_MEMINFO="$FIX/meminfo_ok"
  export HC_NPROC=4 MOCK_DF_OUTPUT="$FIX/df_ok" MOCK_ACTIVE_UNITS="sshd cron"
}

@test "--help prints usage and exits 0" {
  run "$HC" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "--version prints version" {
  run "$HC" --version
  [ "$status" -eq 0 ]
  [[ "$output" =~ [0-9]+\.[0-9]+\.[0-9]+ ]]
}

@test "all checks OK exits 0" {
  run "$HC" -s sshd,cron -p 22,443
  [ "$status" -eq 0 ]
  [[ "$output" == *"OVERALL: OK"* ]]
  [[ "$output" == *"disk:/srv/data"* ]]
}

@test "high load per core triggers WARNING (exit 1)" {
  HC_PROC_LOADAVG="$FIX/loadavg_high" run "$HC" -C cpu
  [ "$status" -eq 1 ]
  echo "$output" | grep -Eq '^\[WARNING\] +cpu '
}

@test "memory over threshold triggers WARNING" {
  HC_PROC_MEMINFO="$FIX/meminfo_warn" run "$HC" -C mem
  [ "$status" -eq 1 ]
  echo "$output" | grep -Eq '^\[WARNING\] +mem '
}

@test "full disk triggers CRITICAL (exit 2)" {
  MOCK_DF_OUTPUT="$FIX/df_crit" run "$HC" -C disk
  [ "$status" -eq 2 ]
  echo "$output" | grep -Eq '^\[CRITICAL\] +disk:/ '
}

@test "inactive service is CRITICAL" {
  run "$HC" -C services -s sshd,nginx
  [ "$status" -eq 2 ]
  echo "$output" | grep -Eq '^\[CRITICAL\] +service:nginx .*not active'
}

@test "missing port is CRITICAL, present ports OK (IPv4 and IPv6)" {
  run "$HC" -C ports -p 22,443,9100,8080
  [ "$status" -eq 2 ]
  echo "$output" | grep -Eq '^\[OK\] +port:443 '
  echo "$output" | grep -Eq '^\[CRITICAL\] +port:8080 .*not listening'
}

@test "custom thresholds via CLI" {
  run "$HC" -C disk --disk-warn 20 --disk-crit 60
  [ "$status" -eq 1 ]
}

@test "JSON output is valid and contains status" {
  command -v jq >/dev/null || skip "jq not installed"
  run "$HC" -f json -s sshd
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "OK" and (.checks | length) >= 4'
}

@test "config file is parsed, CLI overrides config" {
  cfg="$BATS_TEST_TMPDIR/hc.conf"
  printf '# comment\nDISK_WARN=20\nDISK_CRIT=25\nCHECKS="disk"\n' >"$cfg"
  run "$HC" -c "$cfg"
  [ "$status" -eq 2 ]
  run "$HC" --disk-crit 99 -c "$cfg"
  [ "$status" -eq 1 ]
}

@test "config file cannot execute code" {
  cfg="$BATS_TEST_TMPDIR/evil.conf"
  marker="$BATS_TEST_TMPDIR/pwned"
  printf 'SERVICES=$(touch %s)\n' "$marker" >"$cfg"
  run "$HC" -c "$cfg"
  [ "$status" -eq 3 ]
  [ ! -e "$marker" ]
}

@test "unknown config key is rejected" {
  cfg="$BATS_TEST_TMPDIR/bad.conf"
  echo 'PATH=/tmp' >"$cfg"
  run "$HC" -c "$cfg"
  [ "$status" -eq 3 ]
}

@test "invalid input is rejected with exit 3" {
  run "$HC" --mem-warn 150;            [ "$status" -eq 3 ]
  run "$HC" -p 70000;                  [ "$status" -eq 3 ]
  run "$HC" -s 'sshd;rm -rf /';        [ "$status" -eq 3 ]
  run "$HC" -f xml;                    [ "$status" -eq 3 ]
  run "$HC" --disk-warn 95 --disk-crit 90; [ "$status" -eq 3 ]
  run "$HC" --bogus;                   [ "$status" -eq 3 ]
}

@test "unreadable loadavg yields UNKNOWN" {
  HC_PROC_LOADAVG=/nonexistent run "$HC" -C cpu
  [ "$status" -eq 3 ]
}

@test "docker overlay mounts are ignored" {
  run "$HC" -C disk
  [ "$status" -eq 0 ]
  [[ "$output" != *"overlay2"* ]]
}

# ---- banner -----------------------------------------------------------------
# script(1) runs the command on a pseudo-terminal, so stdout/stderr are a TTY.
on_tty() {
  command -v script >/dev/null || skip "script(1) not available"
  run script -qefc "$(printf '%q ' "$@")" /dev/null </dev/null
}

@test "banner is printed on an interactive terminal" {
  on_tty "$HC" -C cpu
  [ "$status" -eq 0 ]
  [[ "$output" == *"Bastion Ops Toolkit"* ]]
  [[ "$output" == *"SERVER HEALTHCHECK"* ]]
  [[ "$output" == *"OVERALL: OK"* ]]
}

@test "banner is not printed when stderr is not a terminal" {
  run "$HC" -C cpu
  [ "$status" -eq 0 ]
  [[ "$output" != *"Bastion Ops Toolkit"* ]]
  [[ "$output" == "[OK]"* ]]
}

@test "--no-banner and NO_BANNER=1 suppress the banner on a terminal" {
  on_tty "$HC" --no-banner -C cpu
  [ "$status" -eq 0 ]
  [[ "$output" != *"Bastion Ops Toolkit"* ]]
  on_tty env NO_BANNER=1 "$HC" -C cpu
  [ "$status" -eq 0 ]
  [[ "$output" != *"Bastion Ops Toolkit"* ]]
}

@test "JSON output never includes the banner, even on a terminal" {
  on_tty "$HC" -f json -C cpu
  [ "$status" -eq 0 ]
  [[ "$output" != *"Bastion Ops Toolkit"* ]]
  printf '%s\n' "$output" | tr -d '\r' | jq -e '.status == "OK"' >/dev/null
}

@test "Nagios exit codes are unchanged on a terminal" {
  export HC_PROC_LOADAVG="$FIX/loadavg_high"
  on_tty "$HC" -C cpu
  [ "$status" -eq 1 ]
  [[ "$output" == *"Bastion Ops Toolkit"* ]]
}

@test "--version shows the banner on a terminal, plain version otherwise" {
  on_tty "$HC" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"Bastion Ops Toolkit"* ]]
  run "$HC" --version
  [[ "$output" =~ ^server-healthcheck\ [0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "README banner matches the runtime banner" {
  on_tty "$HC" --version
  # first ```text block of the README
  expected=$(awk -v fence='```' '$0 == fence "text" { on = 1; next } on && $0 == fence { exit } on' "$ROOT/README.md")
  actual=$(printf '%s\n' "$output" | tr -d '\r')
  [ -n "$expected" ]
  [[ "$actual" == "$expected"* ]]
}
