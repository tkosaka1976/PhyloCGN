# DEPENDENCIES.md — PhyloCGN Environment Setup Guide

> This document describes how to install all external tools required to run PhyloCGN
> **into a user-local directory (`~/.local/bin`)** without requiring `sudo` privileges
> or modifying any system-wide settings.
>
> If you prefer to use Conda or another package manager, feel free to do so instead.

---

## Table of Contents

1. [Design Philosophy](#0-design-philosophy)
2. [Create `~/.local/bin` and Configure PATH](#1-create-localbin-and-configure-path)
3. [Set Up Ruby Environment (rbenv)](#2-set-up-ruby-environment-rbenv)
4. [Install Binary Tools](#3-install-binary-tools)
   - [datasets (NCBI)](#3-1-datasets-ncbi)
   - [DIAMOND](#3-2-diamond)
   - [MMseqs2](#3-3-mmseqs2)
   - [SeqKit](#3-4-seqkit)
   - [MUSCLE 5](#3-5-muscle-5)
   - [VeryFastTree](#3-6-veryfasttree)
5. [Verify All Installations](#4-verify-all-installations)
6. [Create Gemfile (Ruby Dependency Management)](#5-create-gemfile-ruby-dependency-management)
7. [Troubleshooting](#6-troubleshooting)

---

## 0. About This Document

This guide explains how to install each tool's binary into `~/.local/bin`.
The main advantages of this approach are:

- No `sudo` privileges required
- No impact on system-wide settings or other users' environments
- Easy to switch between versions

For language runtimes (Ruby / Python / Julia), this guide uses dedicated version managers
(`rbenv` / `pyenv` / `juliaup`). If you already have these set up via Conda or another
method, that works perfectly fine too.

---

## 1. Create `~/.local/bin` and Configure PATH

Create the directory that will hold all binaries, then add it to your PATH.
**This step is a prerequisite for everything else. Do this first.**

```bash
# Create the directory (safe to run even if it already exists)
mkdir -p ~/.local/bin

# Add to PATH in ~/.bashrc
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc

# Apply the change immediately
source ~/.bashrc
```

### Verify

```bash
echo $PATH | tr ':' '\n' | grep -E "\.local/bin"
# → /home/<yourname>/.local/bin should appear
```

> **Note**: If your shell uses `~/.bash_profile` instead of `~/.bashrc` (common in
> SSH login sessions), add the export line to `~/.bash_profile` instead.

---

## 2. Set Up Ruby Environment (rbenv)

PhyloCGN includes Ruby scripts. Use `rbenv` to manage a Ruby version independently
from the system Ruby.

### 2-1. Install rbenv

```bash
# Clone rbenv
git clone https://github.com/rbenv/rbenv.git ~/.rbenv

# Add PATH and initialization to ~/.bashrc
echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(rbenv init - bash)"' >> ~/.bashrc

# Apply changes
source ~/.bashrc
```

### 2-2. Install the ruby-build Plugin

```bash
git clone https://github.com/rbenv/ruby-build.git \
  ~/.rbenv/plugins/ruby-build
```

### 2-3. Install Ruby

```bash
# Install build dependencies first (Ubuntu)
sudo apt-get update
sudo apt-get install -y \
  build-essential libssl-dev libreadline-dev \
  zlib1g-dev libyaml-dev libffi-dev

# Install Ruby (adjust the version as needed)
rbenv install 3.3.0
rbenv global 3.3.0

# Verify
ruby -v
# → ruby 3.3.0 (2023-12-25 revision ...) [x86_64-linux]
```

### 2-4. Install Bundler

```bash
gem install bundler
bundler -v
```

---

## 3. Install Binary Tools

> **General notes**
> - Version numbers reflect what was current as of April 2026.
> - Always check each tool's GitHub Releases page for the latest version.
> - All commands assume an **x86_64 (amd64)** architecture.
> - For ARM64 environments (e.g. AWS Graviton, Apple Silicon), select the appropriate ARM binary instead.

---

### 3-1. datasets (NCBI)

The official NCBI command-line tool for downloading genome data.

- **Official docs**: https://www.ncbi.nlm.nih.gov/datasets/docs/v2/download-and-install/
- **Latest binary**: https://ftp.ncbi.nlm.nih.gov/pub/datasets/command-line/v2/linux-amd64/

```bash
# Linux (x86_64) — download the binary directly
curl -fSL \
  "https://ftp.ncbi.nlm.nih.gov/pub/datasets/command-line/v2/linux-amd64/datasets" \
  -o ~/.local/bin/datasets

chmod +x ~/.local/bin/datasets

# Verify
datasets --version
```

> The companion tool `dataformat` is often needed alongside `datasets`:
> ```bash
> curl -fSL \
>   "https://ftp.ncbi.nlm.nih.gov/pub/datasets/command-line/v2/linux-amd64/dataformat" \
>   -o ~/.local/bin/dataformat
> chmod +x ~/.local/bin/dataformat
> ```

---

### 3-2. DIAMOND

A high-speed protein sequence aligner compatible with BLAST.

- **GitHub**: https://github.com/bbuchfink/diamond/releases
- **Latest version**: v2.1.24 (as of March 2025)

```bash
DIAMOND_VERSION="2.1.24"

wget -q "https://github.com/bbuchfink/diamond/releases/download/v${DIAMOND_VERSION}/diamond-linux64.tar.gz" \
  -O /tmp/diamond.tar.gz

tar -xzf /tmp/diamond.tar.gz -C /tmp
mv /tmp/diamond ~/.local/bin/diamond
chmod +x ~/.local/bin/diamond

# Clean up
rm /tmp/diamond.tar.gz

# Verify
diamond --version
```

---

### 3-3. MMseqs2

An ultra-fast tool for sequence search and clustering.

- **GitHub**: https://github.com/soedinglab/MMseqs2/releases
- **Latest release**: https://github.com/soedinglab/MMseqs2/releases/latest

```bash
# For AVX2-capable CPUs (most modern servers)
wget -q "https://mmseqs.com/latest/mmseqs-linux-avx2.tar.gz" \
  -O /tmp/mmseqs.tar.gz

tar -xzf /tmp/mmseqs.tar.gz -C /tmp
mv /tmp/mmseqs/bin/mmseqs ~/.local/bin/mmseqs
chmod +x ~/.local/bin/mmseqs

# Clean up
rm -rf /tmp/mmseqs.tar.gz /tmp/mmseqs

# Verify
mmseqs version
```

> **If your CPU does not support AVX2** (older servers), use
> `mmseqs-linux-sse41.tar.gz` or `mmseqs-linux-sse2.tar.gz` instead.
> Check AVX2 support: `grep -m1 'flags' /proc/cpuinfo | grep -o 'avx2'`

---

### 3-4. SeqKit

A fast and versatile toolkit for FASTA/FASTQ file manipulation.

- **GitHub**: https://github.com/shenwei356/seqkit/releases
- **Latest version**: v2.12.0 (as of December 2025)

```bash
SEQKIT_VERSION="2.12.0"

wget -q "https://github.com/shenwei356/seqkit/releases/download/v${SEQKIT_VERSION}/seqkit_linux_amd64.tar.gz" \
  -O /tmp/seqkit.tar.gz

tar -xzf /tmp/seqkit.tar.gz -C /tmp
mv /tmp/seqkit ~/.local/bin/seqkit
chmod +x ~/.local/bin/seqkit

# Clean up
rm /tmp/seqkit.tar.gz

# Verify
seqkit version
```

> For ARM64 environments, use `seqkit_linux_arm64.tar.gz` instead.

---

### 3-5. MUSCLE 5

A high-accuracy multiple sequence alignment tool.

- **GitHub**: https://github.com/rcedgar/muscle/releases
- **Latest version**: v5.3

```bash
MUSCLE_VERSION="5.3"

# Note: the binary filename may vary between releases.
# Always confirm the exact asset name on the GitHub Releases page before running.
wget -q "https://github.com/rcedgar/muscle/releases/download/v${MUSCLE_VERSION}/muscle-linux-amd64.v${MUSCLE_VERSION}" \
  -O ~/.local/bin/muscle5

chmod +x ~/.local/bin/muscle5

# Verify
muscle5 --version
```

> Binary filenames differ between releases (e.g. `muscle5.1.linux_intel64`).
> Check the actual asset name at https://github.com/rcedgar/muscle/releases
> before constructing the download URL.

---

### 3-6. VeryFastTree

A highly optimized phylogenetic tree inference tool designed for massive datasets.

- **GitHub**: https://github.com/citiususc/veryfasttree/releases
- **Latest version**: v4.0.5 (as of April 2025)

```bash
VFT_VERSION="4.0.5"

wget -q "https://github.com/citiususc/veryfasttree/releases/download/v${VFT_VERSION}/VeryFastTree" \
  -O ~/.local/bin/VeryFastTree

chmod +x ~/.local/bin/VeryFastTree

# Verify
VeryFastTree -h 2>&1 | head -3
```

> If no pre-built binary is available for your platform, build from source:
>
> ```bash
> sudo apt-get install -y cmake g++ libomp-dev
>
> git clone https://github.com/citiususc/veryfasttree.git /tmp/veryfasttree
> cd /tmp/veryfasttree
> cmake -DCMAKE_BUILD_TYPE=Release .
> make -j$(nproc)
> cp VeryFastTree ~/.local/bin/
> chmod +x ~/.local/bin/VeryFastTree
> rm -rf /tmp/veryfasttree
> ```

---

## 4. Verify All Installations

Run the following script to confirm that every required tool is installed and accessible on your PATH.

```bash
#!/usr/bin/env bash

echo "=== PhyloCGN Dependency Check ==="
echo ""

TOOLS=(
  "datasets"
  "diamond"
  "mmseqs"
  "seqkit"
  "muscle5"
  "VeryFastTree"
)

ALL_OK=true

for tool in "${TOOLS[@]}"; do
  if command -v "$tool" &>/dev/null; then
    path=$(which "$tool")
    echo "  [OK] $tool -> $path"
  else
    echo "  [NG] $tool -> not found"
    ALL_OK=false
  fi
done

echo ""
if $ALL_OK; then
  echo "All tools are installed and ready."
else
  echo "Some tools are missing. Please refer to DEPENDENCIES.md and complete the installation."
  exit 1
fi
```

To run the script directly:

```bash
# Save the script above as check_deps.sh, then run:
bash check_deps.sh
```

Or verify each tool individually:

```bash
which datasets    && datasets --version
which diamond     && diamond --version
which mmseqs      && mmseqs version
which seqkit      && seqkit version
which muscle5     && muscle5 --version
which VeryFastTree && VeryFastTree -h 2>&1 | head -1
```

---

## 5. Create Gemfile (Ruby Dependency Management)

The current repository does not include a `Gemfile`. Create one with the following steps.

```bash
cd /path/to/PhyloCGN

# Initialize Gemfile
bundle init
```

Once the `Gemfile` is generated, add any gems required by PhyloCGN.
(Check `require` statements in the Ruby scripts to identify what is needed.)

```ruby
# Gemfile (example)
# frozen_string_literal: true

source "https://rubygems.org"

# Add required gems below, for example:
# gem "bio"
# gem "parallel"
```

Then install the gems:

```bash
bundle install
```

---

## 6. Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `command not found` | PATH not applied | Run `source ~/.bashrc` |
| Binary fails to execute | Architecture mismatch | Run `file ~/.local/bin/<tool>` to check; use the ARM binary for ARM64 systems |
| `Permission denied` | Missing execute permission | Re-run `chmod +x ~/.local/bin/<tool>` |
| `wget: command not found` | wget not installed | Run `sudo apt-get install -y wget`, or use `curl` instead |
| MMseqs2 AVX2 error | CPU does not support AVX2 | Use `mmseqs-linux-sse41.tar.gz` instead |
| VeryFastTree build fails | cmake or OpenMP not installed | Run `sudo apt-get install -y cmake libomp-dev` |
| rbenv: `ruby-build` not found | Plugin not installed | Follow the steps in Section 2-2 |

---

## Reference Links

| Tool | Documentation | License |
|------|--------------|---------|
| datasets | https://www.ncbi.nlm.nih.gov/datasets/docs/v2/ | Public Domain |
| DIAMOND | https://github.com/bbuchfink/diamond/wiki | GPL-3.0 |
| MMseqs2 | https://github.com/soedinglab/MMseqs2/wiki | GPL-3.0 |
| SeqKit | https://bioinf.shenwei.me/seqkit/ | MIT |
| MUSCLE 5 | https://drive5.com/muscle5/manual/ | Public Domain |
| VeryFastTree | https://github.com/citiususc/veryfasttree | GPL-3.0 |
| rbenv | https://github.com/rbenv/rbenv | MIT |
