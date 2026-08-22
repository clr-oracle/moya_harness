#!/bin/zsh

set -euo pipefail

results_timestamp() {
  date +"%Y%m%d-%H%M%S"
}

results_file_path() {
  local root="$1"
  local timestamp="$2"
  echo "${root}/logs/results-${timestamp}.txt"
}

write_results_header() {
  local file="$1"
  local run_name="$2"
  local timestamp="$3"

  mkdir -p "$(dirname "$file")"

  cat > "$file" <<EOF
run_name=${run_name}
timestamp=${timestamp}

EOF
}

append_phase_results() {
  local results_file="$1"
  local phase_name="$2"
  local log_file="$3"

  {
    echo "[${phase_name}]"
    echo "manager_log=${log_file}"

    awk '
      function extract(line, pattern, default_value,    value) {
        value = default_value
        if (match(line, pattern)) {
          value = substr(line, RSTART, RLENGTH)
          sub(/^[^=]*=/, "", value)
          sub(/[A-Za-z%]+$/, "", value)
        }
        return value
      }

      function average(sum, count) {
        if (count > 0) {
          return sprintf("%.2f", sum / count)
        }

        return "n/a"
      }

      BEGIN {
        in_warmup = 0
        in_burn = 0
        burn_seen = 0
        warmup_p50_sum = 0
        warmup_p90_sum = 0
        warmup_p95_sum = 0
        warmup_count = 0
        burn_rps_sum = 0
        burn_count = 0
        burn_payload = "n/a"
        burn_connections = "n/a"
      }

      /\[manager\]\[warmup\] seeding keys/ {
        in_warmup = 1
        next
      }

      /\[manager\]\[warmup\] completed/ {
        in_warmup = 0
        next
      }

      /\[manager\]\[burn\]/ {
        in_burn = 1
        burn_seen = 1
        next
      }

      /\[manager\]\[final\]/ {
        in_burn = 0
        next
      }

      /\[manager\]\[sec\]/ {
        if (in_warmup) {
          warmup_p50_sum += extract($0, /p50=[0-9.]+ms/, 0) + 0
          warmup_p90_sum += extract($0, /p90=[0-9.]+ms/, 0) + 0
          warmup_p95_sum += extract($0, /p95=[0-9.]+ms/, 0) + 0
          warmup_count += 1
        }

        if (in_burn) {
          burn_rps_sum += extract($0, /rps=[0-9.]+/, 0) + 0
          burn_count += 1
        }

        next
      }

      /\[manager\] This squeeze test ran until/ {
        if (burn_seen) {
          burn_payload = extract($0, /avg_payload_size=[0-9.]+B/, "n/a")
          burn_connections = extract($0, /concurrent_db_connections=[0-9.]+/, "n/a")
        }
      }

      END {
        print "warmup_avg_p50_ms=" average(warmup_p50_sum, warmup_count)
        print "warmup_avg_p90_ms=" average(warmup_p90_sum, warmup_count)
        print "warmup_avg_p95_ms=" average(warmup_p95_sum, warmup_count)
        print "burn_avg_total_rps=" average(burn_rps_sum, burn_count)
        print "burn_avg_total_concurrent_connections=" burn_connections
        print "burn_avg_payload_size_bytes=" burn_payload
      }
    ' "$log_file"

    echo
  } >> "$results_file"
}
