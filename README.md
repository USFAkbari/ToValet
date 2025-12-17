# ToValet(Shell)

`ToValet.sh` is an interactive Bash script that guides you step‑by‑step through secure SSH setup:

- Generating secure SSH key pairs (ED25519 or RSA)
- Creating and updating `~/.ssh/config` for multiple servers
- **Automatically copying public keys to remote servers using `ssh-copy-id`**
- Ensuring strict permissions on `~/.ssh` and key files
- Testing connections using `ssh -v` for troubleshooting

It is designed for Linux, macOS, and WSL environments where OpenSSH is available.

---

## Features

- **OS‑aware intro**: Detects your OS and prints relevant guidance.
- **Key generation wizard**:
  - Recommends **ED25519** over RSA where possible.
  - Lets you select key type and file path (defaults to `~/.ssh/id_ed25519` or `~/.ssh/id_rsa`).
  - Calls `ssh-keygen` interactively so you can choose a passphrase.
  - Sets secure permissions:
    - `chmod 700 ~/.ssh`
    - `chmod 600 <private_key>`
    - `chmod 644 <private_key>.pub`
- **SSH config management**:
  - Adds or updates entries in `~/.ssh/config`.
  - Backs up the existing config to `~/.ssh/config.bak` before writing.
  - Automatically detects existing SSH keys (prefers ed25519 over rsa).
  - Prompts for:
    - **Host alias** (e.g. `myserver`)
    - **Hostname/IP** (e.g. `192.168.1.50` or `example.com`)
    - **User** (e.g. `root`, defaults to `root`)
    - **Port** (defaults to `22`, supports non‑standard ports like `2222`)
    - **IdentityFile** path to your private key (auto-detects existing keys)
  - Appends a standard OpenSSH block, for example:

    ```sshconfig
    Host myserver
      HostName 192.168.1.50
      User root
      IdentityFile ~/.ssh/id_ed25519
      Port 22
    ```

- **Automated key copying**:
  - Automatically offers to copy your public key using `ssh-copy-id` after creating a config entry.
  - Standalone option to copy keys to existing server configurations.
  - Extracts identity file from SSH config automatically.
  - Optional connection test after successful key copy.
  - Falls back to manual instructions if `ssh-copy-id` is unavailable.

- **Connection testing**:
  - Runs `ssh -v <alias>` with verbose output for debugging auth and networking issues.
- **Config viewing**:
  - Displays the contents of `~/.ssh/config` when requested.
- **Security‑first design**:
  - Never prints or reads private key contents.
  - Reminds you to keep private keys secret and use passphrases where practical.

---

## Requirements

- **OS**: Linux, macOS, or WSL/Unix‑like shell.
- **Tools**:
  - `bash`
  - `ssh-keygen` (from OpenSSH)
  - `ssh` client
  - `ssh-copy-id` (recommended, for automated key copying)

You can verify availability with:

```bash
ssh -V
ssh-keygen -V 2>/dev/null || ssh-keygen -h
ssh-copy-id 2>&1 | head -1  # Check if ssh-copy-id is available
```

---

## Installation

### Quick Install (GitHub)

```bash
# Clone the repository
git clone https://github.com/yourusername/SSH_Config.git
cd SSH_Config

# Make it executable
chmod +x ToValet.sh

# Run it
./ToValet.sh
```

### System-wide Install

You can optionally place it on your `PATH`:

```bash
sudo cp ToValet.sh /usr/local/bin/ToValet
sudo chmod +x /usr/local/bin/ToValet
```

Then run it simply as:

```bash
ToValet
```

### Install ssh-copy-id (if not available)

- **Debian/Ubuntu**: `sudo apt install openssh-client`
- **macOS**: Usually pre-installed
- **RHEL/CentOS**: `sudo yum install openssh-clients`
- **Arch Linux**: `sudo pacman -S openssh`

---

## Usage

From the project directory:

```bash
./ToValet.sh
```

You will see a menu like:

```text
ToValet (shell)
---------------
Detected OS: Linux

Security reminders:
  - NEVER share your private SSH key.
  - Use ed25519 keys when possible; use rsa only if required by older systems.

Main menu:
  1) Generate new SSH key
  2) Add or update SSH config entry
  3) Copy public key to server (ssh-copy-id)
  4) Test SSH connection
  5) View SSH config
  q) Quit
```

### 1) Generate new SSH key

- Choose key type: `ed25519` (recommended) or `rsa`.
- Confirm or change the key file path:
  - Defaults:
    - `~/.ssh/id_ed25519` for ED25519
    - `~/.ssh/id_rsa` for RSA
- Confirm or change the key comment (defaults to `user@hostname`).
- `ssh-keygen` then runs interactively so you can:
  - Set a **passphrase** (recommended on laptops and shared systems).
  - Confirm key creation.

After completion, the script sets restrictive permissions and prints:

- Path to the **private key**.
- Path to the **public key** (`.pub` file).

> **Never share the private key file.** Only share the `.pub` file with remote servers.

### 2) Add or update SSH config entry

You will be prompted for:

- **Host alias**: A short name (e.g. `myserver`).
- **Hostname or IP**: e.g. `192.168.1.50` or `myserver.example.com`.
- **SSH username**: Defaults to `root` (you can change it to any user).
- **SSH port**: Defaults to `22`; you can enter `2222` or any valid port.
- **IdentityFile**: Path to your private key (auto-detects existing keys, defaults to `~/.ssh/id_ed25519` if none found).

After creating the config entry, the script will automatically offer to copy your public key to the remote server using `ssh-copy-id`.

The script then shows you the exact config block to be written and asks for confirmation.
If confirmed, it:

1. Creates `~/.ssh` if needed and sets `chmod 700 ~/.ssh`.
2. Backs up `~/.ssh/config` to `~/.ssh/config.bak` (if it exists).
3. Appends a block like:

   ```sshconfig
   # Added by ToValet
   Host myserver
     HostName 192.168.1.50
     User ubuntu
     IdentityFile ~/.ssh/id_ed25519
     Port 22
   ```

4. Sets `chmod 600 ~/.ssh/config` where supported.

### 3) Copy public key to server (ssh-copy-id)

- Prompts you for the **Host alias** you configured.
- Automatically detects the identity file from your SSH config.
- Displays the public key that will be copied.
- Runs `ssh-copy-id` to automatically add your key to the remote server's `~/.ssh/authorized_keys`.
- Offers an optional connection test after successful copy.
- Provides manual instructions if `ssh-copy-id` fails or is unavailable.

**Note**: You'll need to enter the remote server password once during the copy process.

### 4) Test SSH connection

- Prompts you for the **Host alias** you configured (e.g. `myserver`).
- Runs:

  ```bash
  ssh -v myserver
  ```

- Shows verbose debug output, which is very useful for:
  - `Permission denied (publickey)` errors.
  - Host key mismatches.
  - Network reachability issues.

You can exit this test with `Ctrl+C` or by closing the SSH session.

### 5) View SSH config

- Prints the contents of `~/.ssh/config` if it exists.
- Helpful for quickly verifying your aliases, ports, and identity files.

---

## Typical Workflow Example

1. **Generate a secure key**:

   - Choose option `1` in the menu.
   - Use key type **ed25519**.
   - Accept default path `~/.ssh/id_ed25519`.
   - Set a passphrase (recommended).

2. **Add a new server config**:

   - Choose option `2`.
   - Host alias: `my-server`
   - Hostname: `192.168.1.50`
   - User: `root` (or change to your preferred user)
   - Port: `22` (or `2222` if non‑standard)
   - IdentityFile: `~/.ssh/id_ed25519` (auto-detected if it exists)
   - The script will automatically offer to copy your public key using `ssh-copy-id`.

3. **Copy your public key to the remote server**:

   - If you accepted the automatic copy in step 2, your key is already copied!
   - Or use option `3` to copy keys to existing server configurations.
   - You'll be prompted for the remote server password once.

4. **Test the connection**:

   - Choose option `4` and enter `my-server`.
   - Ensure the connection works without a password.

---

## Security and Permission Tips

- **Private key permissions (local)**:

  ```bash
  chmod 700 ~/.ssh
  chmod 600 ~/.ssh/id_ed25519    # or id_rsa
  chmod 644 ~/.ssh/id_ed25519.pub
  ```

- **Remote `authorized_keys`**:

  ```bash
  mkdir -p ~/.ssh && chmod 700 ~/.ssh
  chmod 600 ~/.ssh/authorized_keys
  ```

- Never paste or commit your private key into version control or chat systems.

---

## Troubleshooting

- **`Permission denied (publickey)`**:
  - Ensure the correct public key is in `~/.ssh/authorized_keys` on the remote host.
  - Verify `IdentityFile` in `~/.ssh/config` points to the right private key.
  - Check local permissions as above (700 for `~/.ssh`, 600 for private key).
- **`ssh` or `ssh-keygen` not found**:
  - Install OpenSSH client (e.g. `sudo apt install openssh-client` on Debian/Ubuntu).
- **Non‑standard port (e.g., 2222)**:
  - When using option `2`, set port to `2222`.
  - Then connect simply as: `ssh <alias>` without specifying `-p`.

---

## Contributing

Special thanks to my dear friend [Kianam Ghahari](https://www.linkedin.com/in/kianam-qahari-1b1177247/) for inspiring the project name and idea ❤️.

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
