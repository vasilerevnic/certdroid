#!/usr/bin/env bash
# Shared host helpers. Source from host scripts after setting DIR to the project root.
shell_quote() {
  local rest=$1
  printf '%s' "'"
  while [[ "$rest" == *"'"* ]]; do
    printf '%s' "${rest%%\'*}" "'\\''"
    rest=${rest#*\'}
  done
  printf "%s'" "$rest"
}
root_command() { "${ADB[@]}" shell -T "su -c $(shell_quote "$1")"; }
certificate_constraints() {
  local output
  # Probe a real operation on a certificate already known to be readable.
  openssl x509 -in "$1" -noout >/dev/null || return 1
  if ! output=$(openssl x509 -in "$1" -noout -ext basicConstraints 2>&1); then
    printf '%s\n' "$output" >&2
    echo 'Cannot read basicConstraints. OpenSSL with x509 -ext support is required; on macOS: brew install openssl@3 and add its bin directory to PATH.' >&2
    return 1
  fi
  printf '%s\n' "$output"
}
validate_certs() {
  local cert name hash text count=0
  for cert in "$DIR"/cacerts/*; do
    [[ -f "$cert" && ! -L "$cert" ]] || continue
    name=${cert##*/}
    [[ "$name" =~ ^[0-9a-f]{8}\.[0-9]+$ ]] || { echo "Invalid certificate filename: $name" >&2; return 1; }
    hash=$(openssl x509 -in "$cert" -subject_hash_old -noout) || return 1
    [[ "${name%.*}" == "$hash" ]] || { echo "Wrong subject hash: $name" >&2; return 1; }
    text=$(certificate_constraints "$cert") || return 1
    [[ "$text" == *CA:TRUE* ]] || { echo "Not a CA certificate: $name" >&2; return 1; }
    openssl x509 -in "$cert" -checkend 0 -noout >/dev/null || { echo "Expired CA: $name" >&2; return 1; }
    count=$((count + 1))
  done
  ((count > 0)) || { echo 'No CA certificates; run prepare-cert.sh first.' >&2; return 1; }
}
