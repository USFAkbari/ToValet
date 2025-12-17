#!/usr/bin/env bash
#
# ToValet - interactive SSH setup helper (shell version)
# -----------------------------------------------------
# This script guides you through:
#   - Generating an SSH key pair (ed25519 or rsa)
#   - Creating/updating ~/.ssh/config entries
#   - Automatically copying public keys to remote servers using ssh-copy-id
#   - Ensuring correct permissions on ~/.ssh and key files
#   - Testing connections with `ssh -v`
#
# Security notes:
#   - NEVER share your private key (~/.ssh/id_* without .pub).
#   - Only the .pub file is meant to be shared with remote servers.
#   - Prefer ed25519 keys when supported; use rsa only if necessary.
#

set -euo pipefail

SSH_DIR="${HOME}/.ssh"
CONFIG_FILE="${SSH_DIR}/config"

detect_os() {
  local uname_out
  uname_out=$(uname -s 2>/dev/null || echo "Unknown")
  case "${uname_out}" in
    Linux*)   echo "Linux" ;;
    Darwin*)  echo "macOS" ;;
    CYGWIN*|MINGW*|MSYS*) echo "Windows" ;;
    *)        echo "Unknown" ;;
  esac
}

ensure_ssh_dir() {
  mkdir -p "${SSH_DIR}"
  chmod 700 "${SSH_DIR}" 2>/dev/null || true
}

find_existing_key() {
  # Try to find an existing SSH key, preferring ed25519 over rsa
  local key_path=""
  if [[ -f "${SSH_DIR}/id_ed25519" ]]; then
    key_path="${SSH_DIR}/id_ed25519"
  elif [[ -f "${SSH_DIR}/id_rsa" ]]; then
    key_path="${SSH_DIR}/id_rsa"
  fi
  echo "${key_path}"
}

prompt_yes_no() {
  local question="$1"
  local default="${2:-Y}" # Y or N
  local suffix
  if [[ "${default}" == "Y" ]]; then
    suffix="[Y/n]"
  else
    suffix="[y/N]"
  fi
  while true; do
    read -r -p "${question} ${suffix} " answer || answer=""
    answer="${answer:-${default}}"
    case "${answer}" in
      [Yy]) return 0 ;;
      [Nn]) return 1 ;;
      *) echo "Please answer y or n." ;;
    esac
  done
}

prompt_with_default() {
  local prompt="$1"
  local default="${2:-}"
  local value
  if [[ -n "${default}" ]]; then
    read -r -p "${prompt} [${default}]: " value || value=""
    echo "${value:-${default}}"
  else
    read -r -p "${prompt}: " value || value=""
    echo "${value}"
  fi
}

step_generate_key() {
  echo
  echo "=== Step 1: Generate SSH key pair ==="
  echo "Security recommendation: use 'ed25519' where supported; fall back to 'rsa' only if necessary."
  echo

  if ! command -v ssh-keygen >/dev/null 2>&1; then
    echo "Error: ssh-keygen not found in PATH. Please install the OpenSSH client tools first."
    return
  fi

  local key_type
  key_type=$(prompt_with_default "Key type (ed25519/rsa)" "ed25519")
  key_type=$(echo "${key_type}" | tr '[:upper:]' '[:lower:]')
  if [[ "${key_type}" != "ed25519" && "${key_type}" != "rsa" ]]; then
    echo "Unsupported key type; using ed25519."
    key_type="ed25519"
  fi

  ensure_ssh_dir
  local suggested_path
  if [[ "${key_type}" == "rsa" ]]; then
    suggested_path="${SSH_DIR}/id_rsa"
  else
    suggested_path="${SSH_DIR}/id_ed25519"
  fi

  local key_path
  key_path=$(prompt_with_default "Private key path" "${suggested_path}")

  local comment_default
  comment_default="${USER}@$(hostname 2>/dev/null || echo "host")"
  local comment
  comment=$(prompt_with_default "Key comment" "${comment_default}")

  echo
  echo "ssh-keygen will be run interactively so you can choose a passphrase."
  echo "Planned command:"
  echo "  ssh-keygen -t ${key_type} -f \"${key_path}\" -C \"${comment}\""
  echo

  if ! prompt_yes_no "Proceed with key generation?" "Y"; then
    echo "Key generation cancelled."
    return
  fi

  ssh-keygen -t "${key_type}" -f "${key_path}" -C "${comment}"

  # Permissions
  chmod 700 "${SSH_DIR}" 2>/dev/null || true
  chmod 600 "${key_path}" 2>/dev/null || true
  if [[ -f "${key_path}.pub" ]]; then
    chmod 644 "${key_path}.pub" 2>/dev/null || true
  fi

  echo
  echo "Key generation complete."
  echo "Private key: ${key_path}"
  if [[ -f "${key_path}.pub" ]]; then
    echo "Public key:  ${key_path}.pub"
  fi
  echo
  echo "Security reminder: NEVER share your private key file; only share the .pub file."
}

step_add_server_config() {
  echo
  echo "=== Step 2: Create SSH config entry (ToValet) ==="

  ensure_ssh_dir

  local host_alias hostname user port identity_file
  host_alias=$(prompt_with_default "Host alias (short name)" "myserver")
  while [[ -z "${host_alias}" ]]; do
    echo "Host alias cannot be empty."
    host_alias=$(prompt_with_default "Host alias (short name)" "myserver")
  done

  hostname=$(prompt_with_default "Hostname or IP" "")
  while [[ -z "${hostname}" ]]; do
    echo "Hostname/IP cannot be empty."
    hostname=$(prompt_with_default "Hostname or IP" "")
  done

  user=$(prompt_with_default "SSH username" "root")
  while [[ -z "${user}" ]]; do
    echo "Username cannot be empty."
    user=$(prompt_with_default "SSH username" "root")
  done

  port=$(prompt_with_default "SSH port" "22")
  if ! [[ "${port}" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
    echo "Invalid port; using 22."
    port=22
  fi

  local default_key
  default_key=$(find_existing_key)
  if [[ -z "${default_key}" ]]; then
    default_key="${SSH_DIR}/id_ed25519"
  fi
  identity_file=$(prompt_with_default "Path to private key (IdentityFile)" "${default_key}")
  
  # Validate that the key file exists
  if [[ ! -f "${identity_file}" ]]; then
    echo
    echo "Warning: Private key not found at ${identity_file}"
    if ! prompt_yes_no "Continue anyway? (You can generate a key later with option 1)" "N"; then
      echo "Config creation cancelled."
      return
    fi
  fi

  echo
  echo "SSH config entry to be added to ${CONFIG_FILE} (managed by ToValet):"
  echo "-----"
  echo "Host ${host_alias}"
  echo "  HostName ${hostname}"
  echo "  User ${user}"
  echo "  IdentityFile ${identity_file}"
  if [[ "${port}" != "22" ]]; then
    echo "  Port ${port}"
  fi
  echo "-----"
  echo

  if ! prompt_yes_no "Append this block to ${CONFIG_FILE}?" "Y"; then
    echo "Config update cancelled."
    return
  fi

  # Backup existing config
  if [[ -f "${CONFIG_FILE}" ]]; then
    cp -p "${CONFIG_FILE}" "${CONFIG_FILE}.bak" 2>/dev/null || true
  fi

  {
    echo "# Added by ToValet"
    echo "Host ${host_alias}"
    echo "  HostName ${hostname}"
    echo "  User ${user}"
    echo "  IdentityFile ${identity_file}"
    if [[ "${port}" != "22" ]]; then
      echo "  Port ${port}"
    fi
    echo
  } >> "${CONFIG_FILE}"

  chmod 600 "${CONFIG_FILE}" 2>/dev/null || true

  echo "Config updated successfully."
  echo
  
  # Offer to copy public key
  local pub_key="${identity_file}.pub"
  if [[ -f "${pub_key}" ]]; then
    echo
    if prompt_yes_no "Copy public key to ${host_alias} using ssh-copy-id now?" "Y"; then
      echo
      if command -v ssh-copy-id >/dev/null 2>&1; then
        echo "Running: ssh-copy-id -i ${pub_key} ${host_alias}"
        echo "You may be prompted for the remote server password."
        echo
        if ssh-copy-id -i "${pub_key}" "${host_alias}" 2>&1; then
          echo
          echo "✓ Public key copied successfully!"
          echo "You should now be able to SSH to ${host_alias} without a password."
          echo
          if prompt_yes_no "Test the connection now?" "Y"; then
            echo
            ssh -o BatchMode=yes -o ConnectTimeout=5 "${host_alias}" "echo 'Connection successful!'" 2>/dev/null && {
              echo "✓ Connection test passed!"
            } || {
              echo "Connection test failed or requires interaction."
              echo "You can test manually with: ssh ${host_alias}"
            }
          fi
        else
          echo
          echo "✗ ssh-copy-id failed. You can try again later (option 3)."
          echo
          echo "Manual method:"
          echo "  mkdir -p ~/.ssh && chmod 700 ~/.ssh"
          echo "  echo '<YOUR_PUBLIC_KEY_LINE>' >> ~/.ssh/authorized_keys"
          echo "  chmod 600 ~/.ssh/authorized_keys"
        fi
      else
        echo "ssh-copy-id not found. Please install openssh-client or use option 3 later."
        echo
        echo "Manual method:"
        echo "  mkdir -p ~/.ssh && chmod 700 ~/.ssh"
        echo "  echo '<YOUR_PUBLIC_KEY_LINE>' >> ~/.ssh/authorized_keys"
        echo "  chmod 600 ~/.ssh/authorized_keys"
      fi
    fi
  else
    echo
    echo "Note: Public key not found at ${pub_key}"
    echo "Generate a key first (option 1) or copy it manually later (option 3)."
  fi
}

step_copy_public_key() {
  echo
  echo "=== Copy public key to remote server (ssh-copy-id) ==="
  
  if ! command -v ssh-copy-id >/dev/null 2>&1; then
    echo "Error: ssh-copy-id not found in PATH."
    echo "Please install it first:"
    echo "  - Debian/Ubuntu: sudo apt install openssh-client"
    echo "  - macOS: usually pre-installed"
    echo "  - Or use manual method shown below"
    return 1
  fi

  local host_alias
  host_alias=$(prompt_with_default "Host alias to copy key to" "myserver")
  while [[ -z "${host_alias}" ]]; do
    echo "Host alias cannot be empty."
    host_alias=$(prompt_with_default "Host alias to copy key to" "myserver")
  done

  # Try to get identity file from config
  local identity_file=""
  if [[ -f "${CONFIG_FILE}" ]]; then
    # Extract IdentityFile from config for this host
    local in_host=false
    while IFS= read -r line; do
      if [[ "${line}" =~ ^[[:space:]]*Host[[:space:]]+${host_alias}$ ]]; then
        in_host=true
      elif [[ "${in_host}" == true && "${line}" =~ ^[[:space:]]*Host[[:space:]] ]]; then
        break
      elif [[ "${in_host}" == true && "${line}" =~ IdentityFile[[:space:]]+(.+) ]]; then
        identity_file="${BASH_REMATCH[1]}"
        # Expand ~ if present
        identity_file="${identity_file/#\~/${HOME}}"
        break
      fi
    done < "${CONFIG_FILE}"
  fi

  # If not found in config, prompt for it
  if [[ -z "${identity_file}" ]] || [[ ! -f "${identity_file}" ]]; then
    local default_key
    default_key=$(find_existing_key)
    if [[ -z "${default_key}" ]]; then
      default_key="${SSH_DIR}/id_ed25519"
    fi
    identity_file=$(prompt_with_default "Path to private key" "${default_key}")
    
    # Validate that the key file exists
    if [[ ! -f "${identity_file}" ]]; then
      echo
      echo "Error: Private key not found at ${identity_file}"
      echo "Please generate a key first (option 1)."
      return 1
    fi
  fi

  local pub_key="${identity_file}.pub"
  if [[ ! -f "${pub_key}" ]]; then
    echo "Error: Public key not found at ${pub_key}"
    echo "Please generate a key first (option 1)."
    return 1
  fi

  echo
  echo "Public key to copy:"
  cat "${pub_key}"
  echo
  echo "Target: ${host_alias}"
  echo

  if ! prompt_yes_no "Copy this public key to ${host_alias} using ssh-copy-id?" "Y"; then
    echo "Key copy cancelled."
    return
  fi

  echo
  echo "Running: ssh-copy-id -i ${pub_key} ${host_alias}"
  echo "You may be prompted for the remote server password."
  echo

  if ssh-copy-id -i "${pub_key}" "${host_alias}" 2>&1; then
    echo
    echo "✓ Public key copied successfully!"
    echo "You should now be able to SSH to ${host_alias} without a password."
    echo
    if prompt_yes_no "Test the connection now?" "Y"; then
      echo
      ssh -o BatchMode=yes -o ConnectTimeout=5 "${host_alias}" "echo 'Connection successful!'" 2>/dev/null && {
        echo "✓ Connection test passed!"
      } || {
        echo "Connection test failed or requires interaction."
        echo "You can test manually with: ssh ${host_alias}"
      }
    fi
  else
    echo
    echo "✗ ssh-copy-id failed."
    echo
    echo "Manual method:"
    echo "1. Copy the public key shown above"
    echo "2. SSH to the server (you may need password): ssh ${host_alias}"
    echo "3. Run on the server:"
    echo "   mkdir -p ~/.ssh && chmod 700 ~/.ssh"
    echo "   echo 'PASTE_PUBLIC_KEY_HERE' >> ~/.ssh/authorized_keys"
    echo "   chmod 600 ~/.ssh/authorized_keys"
    return 1
  fi
}

step_test_connection() {
  echo
  echo "=== Step 3: Test SSH connection ==="

  if ! command -v ssh >/dev/null 2>&1; then
    echo "Error: ssh client not found in PATH. Please install the OpenSSH client first."
    return
  fi

  local host_alias
  host_alias=$(prompt_with_default "Host alias to test" "myserver")
  while [[ -z "${host_alias}" ]]; do
    echo "Host alias cannot be empty."
    host_alias=$(prompt_with_default "Host alias to test" "myserver")
  done

  echo
  echo "Running: ssh -v ${host_alias}"
  echo "Press Ctrl+C to cancel."
  echo
  ssh -v "${host_alias}" || true
}

step_view_config() {
  echo
  echo "=== Step 4: View ${CONFIG_FILE} (ToValet) ==="
  if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "No SSH config file found at ${CONFIG_FILE}."
    return
  fi
  echo
  cat "${CONFIG_FILE}"
}

main_menu() {
  local os_name
  os_name=$(detect_os)

  echo "ToValet (shell)"
  echo "---------------"
  echo "Detected OS: ${os_name}"
  echo
  echo "Security reminders:"
  echo "  - NEVER share your private SSH key."
  echo "  - Use ed25519 keys when possible; use rsa only if required by older systems."

  while true; do
    echo
    echo "Main menu:"
    echo "  1) Generate new SSH key"
    echo "  2) Add or update SSH config entry"
    echo "  3) Copy public key to server (ssh-copy-id)"
    echo "  4) Test SSH connection"
    echo "  5) View SSH config"
    echo "  q) Quit"
    read -r -p "Select an option: " choice || choice="q"
    case "${choice}" in
      1) step_generate_key ;;
      2) step_add_server_config ;;
      3) step_copy_public_key ;;
      4) step_test_connection ;;
      5) step_view_config ;;
      q|Q) echo "Goodbye."; break ;;
      *) echo "Invalid choice, please enter 1, 2, 3, 4, 5, or q." ;;
    esac
  done
}

main_menu "$@"


