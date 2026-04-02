# DEPENDENCIES.md — PhyloCGN 依存環境構築ガイド

> このドキュメントは、PhyloCGN を動作させるために必要な外部ツールを
> **ユーザーのローカル環境（`~/.local/bin`）に手動でインストールする手順**をまとめたものです。
> `sudo` 権限が不要で、システム環境に影響を与えずにセットアップが完結します。
>
> Conda や他のパッケージマネージャーを使いたい場合は、そちらの手順に従ってください。

---

## 目次

1. [設計方針](#0-設計方針)
2. [`~/.local/bin` の作成と PATH 設定](#1-localbin-の作成と-path-設定)
3. [Ruby 環境の構築（rbenv）](#2-ruby-環境の構築rbenv)
4. [バイナリツールのインストール](#3-バイナリツールのインストール)
   - [datasets（NCBI）](#3-1-datasetsncbi)
   - [DIAMOND](#3-2-diamond)
   - [MMseqs2](#3-3-mmseqs2)
   - [SeqKit](#3-4-seqkit)
   - [MUSCLE 5](#3-5-muscle-5)
   - [VeryFastTree](#3-6-veryfasttree)
5. [インストール確認（一括）](#4-インストール確認一括)
6. [Ruby gem のインストール](#5-ruby-gem-のインストール)
7. [トラブルシューティング](#6-トラブルシューティング)

---

## 0. このドキュメントについて

このガイドでは、各ツールのバイナリを `~/.local/bin` に配置する方法を説明します。
この方法の主な利点は以下の通りです。

- `sudo` 権限が不要
- システム環境やグローバルな設定に影響しない
- 複数バージョンの切り替えも容易

言語系ツール（Ruby / Python / Julia）については、各言語専用のバージョン管理ツール
（`rbenv` / `pyenv` / `juliaup`）を使う手順を示します。
Conda や他の方法で環境構築済みの場合は、そちらをそのまま使って問題ありません。

---

## 1. 前提：システムパッケージの確認

以降の手順では `curl`、`wget`、`unzip`、`git` を使います。
Ubuntu Server では標準で入っていない場合があるため、まとめて確認・インストールしてください。

```bash
sudo apt-get update
sudo apt-get install -y curl wget unzip git
```

---

## 2. `~/.local/bin` の作成と PATH 設定

すべてのバイナリを格納するディレクトリを作成し、PATH に追加します。
**このステップはすべての手順の前提となります。最初に必ず実施してください。**

```bash
# ディレクトリ作成（すでに存在していてもエラーにならない）
mkdir -p ~/.local/bin

# PATH を通す（~/.bashrc に追記）
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc

# 設定を即時反映
source ~/.bashrc
```

### 確認

```bash
echo $PATH | tr ':' '\n' | grep -E "\.local/bin"
# → /home/<yourname>/.local/bin が表示されれば OK
```

> **注意**: `~/.bash_profile` を使っている環境では、`~/.bashrc` の代わりに
> `~/.bash_profile` へ追記してください。SSH ログイン環境では `~/.bash_profile`
> が優先される場合があります。

---

## 2. Ruby 環境の構築（rbenv）

PhyloCGN は Ruby スクリプトを含みます。`rbenv` を使い、システムの Ruby とは
独立したバージョンを管理します。

### 2-1. rbenv のインストール

```bash
# rbenv 本体をクローン
git clone https://github.com/rbenv/rbenv.git ~/.rbenv

# PATH と初期化設定を ~/.bashrc に追記
echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(rbenv init - bash)"' >> ~/.bashrc

# 設定を反映
source ~/.bashrc
```

### 2-2. ruby-build プラグインのインストール

```bash
git clone https://github.com/rbenv/ruby-build.git \
  ~/.rbenv/plugins/ruby-build
```

### 2-3. Ruby のインストール

```bash
# ビルドに必要なシステムライブラリを事前にインストール（Ubuntu）
sudo apt-get update
sudo apt-get install -y \
  build-essential libssl-dev libreadline-dev \
  zlib1g-dev libyaml-dev libffi-dev

# Ruby をインストール（バージョンは適宜変更）
rbenv install 3.3.0
rbenv global 3.3.0

# 確認
ruby -v
# → ruby 3.3.0 (2023-12-25 revision ...) [x86_64-linux]
```

### 2-4. Bundler のインストール

```bash
gem install bundler
bundler -v
```

---

## 3. バイナリツールのインストール

> **共通の注意事項**
> - バージョン番号は執筆時点（2026年4月）のものです。
> - 最新版は各ツールの GitHub Releases ページで確認してください。
> - すべてのコマンドは x86_64（amd64）アーキテクチャを前提としています。
> - ARM64 環境（例: AWS Graviton, Apple Silicon）では別途バイナリを選択してください。

---

### 3-1. datasets（NCBI）

NCBI からゲノムデータを取得するための公式コマンドラインツールです。

- **公式サイト**: https://www.ncbi.nlm.nih.gov/datasets/docs/v2/download-and-install/
- **最新版確認**: https://ftp.ncbi.nlm.nih.gov/pub/datasets/command-line/v2/linux-amd64/

```bash
# Linux (x86_64) — 直接バイナリをダウンロード
curl -fSL \
  "https://ftp.ncbi.nlm.nih.gov/pub/datasets/command-line/v2/linux-amd64/datasets" \
  -o ~/.local/bin/datasets

chmod +x ~/.local/bin/datasets

# 確認
datasets --version
```

> `dataformat` も合わせて必要な場合は同様にインストールします:
> ```bash
> curl -fSL \
>   "https://ftp.ncbi.nlm.nih.gov/pub/datasets/command-line/v2/linux-amd64/dataformat" \
>   -o ~/.local/bin/dataformat
> chmod +x ~/.local/bin/dataformat
> ```

---

### 3-2. DIAMOND

高速なタンパク質配列アライメントツールです（BLAST 互換）。

- **GitHub**: https://github.com/bbuchfink/diamond/releases
- **最新版**: v2.1.24（2025年3月時点）

```bash
DIAMOND_VERSION="2.1.24"

wget -q "https://github.com/bbuchfink/diamond/releases/download/v${DIAMOND_VERSION}/diamond-linux64.tar.gz" \
  -O /tmp/diamond.tar.gz

tar -xzf /tmp/diamond.tar.gz -C /tmp
mv /tmp/diamond ~/.local/bin/diamond
chmod +x ~/.local/bin/diamond

# 後片付け
rm /tmp/diamond.tar.gz

# 確認
diamond --version
```

---

### 3-3. MMseqs2

超高速の配列検索・クラスタリングツールです。

- **GitHub**: https://github.com/soedinglab/MMseqs2/releases
- **最新版確認**: https://github.com/soedinglab/MMseqs2/releases/latest

```bash
# AVX2 対応 CPU（多くのサーバーで有効）
wget -q "https://mmseqs.com/latest/mmseqs-linux-avx2.tar.gz" \
  -O /tmp/mmseqs.tar.gz

tar -xzf /tmp/mmseqs.tar.gz -C /tmp
mv /tmp/mmseqs/bin/mmseqs ~/.local/bin/mmseqs
chmod +x ~/.local/bin/mmseqs

# 後片付け
rm -rf /tmp/mmseqs.tar.gz /tmp/mmseqs

# 確認
mmseqs version
```

> **AVX2 非対応 CPU の場合**（古いサーバー等）は `mmseqs-linux-sse41.tar.gz` または
> `mmseqs-linux-sse2.tar.gz` を使用してください。
> CPU 対応を確認: `grep -m1 'flags' /proc/cpuinfo | grep -o 'avx2'`

---

### 3-4. SeqKit

FASTA/FASTQ ファイルを高速に操作するツールキットです。

- **GitHub**: https://github.com/shenwei356/seqkit/releases
- **最新版**: v2.12.0（2025年12月時点）

```bash
SEQKIT_VERSION="2.12.0"

wget -q "https://github.com/shenwei356/seqkit/releases/download/v${SEQKIT_VERSION}/seqkit_linux_amd64.tar.gz" \
  -O /tmp/seqkit.tar.gz

tar -xzf /tmp/seqkit.tar.gz -C /tmp
mv /tmp/seqkit ~/.local/bin/seqkit
chmod +x ~/.local/bin/seqkit

# 後片付け
rm /tmp/seqkit.tar.gz

# 確認
seqkit version
```

> ARM64 環境の場合は `seqkit_linux_arm64.tar.gz` を使用してください。

---

### 3-5. MUSCLE 5

高精度の多重配列アライメントツールです。

- **GitHub**: https://github.com/rcedgar/muscle/releases
- **最新版**: v5.3（2024年時点）

```bash
MUSCLE_VERSION="5.3"

# バイナリ名はバージョンによって異なる場合があります
# 最新版の正確なファイル名は GitHub Releases ページで確認してください
wget -q "https://github.com/rcedgar/muscle/releases/download/v${MUSCLE_VERSION}/muscle-linux-amd64.v${MUSCLE_VERSION}" \
  -O ~/.local/bin/muscle5

chmod +x ~/.local/bin/muscle5

# 確認
muscle5 --version
```

> バイナリファイル名がバージョンによって変わることがあります（例: `muscle5.1.linux_intel64`）。
> GitHub Releases ページで実際のアセット名を確認してから URL を組み立ててください:
> https://github.com/rcedgar/muscle/releases

---

### 3-6. VeryFastTree

大規模データセット向けの高速系統樹推定ツールです。

- **GitHub**: https://github.com/citiususc/veryfasttree/releases
- **最新版**: v4.0.5（2025年4月時点）

```bash
VFT_VERSION="4.0.5"

wget -q "https://github.com/citiususc/veryfasttree/releases/download/v${VFT_VERSION}/VeryFastTree" \
  -O ~/.local/bin/VeryFastTree

chmod +x ~/.local/bin/VeryFastTree

# 確認
VeryFastTree -h 2>&1 | head -3
```

> VeryFastTree はバージョン番号付きアセット名が公式にリリースされない場合があります。
> その際はリポジトリをクローンしてビルドしてください:
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

## 4. インストール確認（一括）

以下のスクリプトを実行して、すべてのツールが正しくインストールされているか確認します。

```bash
#!/usr/bin/env bash

echo "=== PhyloCGN 依存ツール インストール確認 ==="
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
    echo "  [OK] $tool → $path"
  else
    echo "  [NG] $tool → not found"
    ALL_OK=false
  fi
done

echo ""
if $ALL_OK; then
  echo "すべてのツールが正常にインストールされています。"
else
  echo "見つからないツールがあります。本ドキュメント（DEPENDENCIES.md）を参照して"
  echo "インストールを完了させてください。"
  exit 1
fi
```

このスクリプトを直接実行する場合:

```bash
# 上記スクリプトを check_deps.sh として保存して実行
bash check_deps.sh
```

または個別に確認する場合:

```bash
which datasets   && datasets --version
which diamond    && diamond --version
which mmseqs     && mmseqs version
which seqkit     && seqkit version
which muscle5    && muscle5 --version
which VeryFastTree && VeryFastTree -h 2>&1 | head -1
```

---

## 5. Ruby gem のインストール

PhyloCGN は `rake`（タスクランナー）、`sequel`（データベース操作）、および
`sqlite3`（SQLite3 バインディング）を使用します。

### 5-1. rake

`rake` は Ruby に同梱されている場合がありますが、念のか確認してインストールしてください。

```bash
# インストール済みか確認
gem list rake

# インストール（未インストールの場合）
gem install rake

# 確認
rake --version
```

### 5-2. sequel

Ruby でデータベース操作を行うための ORM ライブラリです。

```bash
gem install sequel

# 確認
gem list sequel
```

### 5-3. sqlite3

`sequel` から SQLite3 データベースを使うために必要な Ruby バインディングです。
コンパイルが必要なため、事前にシステムの SQLite3 開発ライブラリをインストールしてください。

```bash
# SQLite3 の開発ライブラリをインストール（Ubuntu）
sudo apt-get install -y libsqlite3-dev

# gem をインストール
gem install sqlite3

# 確認
gem list sqlite3
```

---

## 6. トラブルシューティング

| 症状 | 原因 | 対処法 |
|------|------|--------|
| `command not found` | PATH が反映されていない | `source ~/.bashrc` を実行する |
| バイナリが起動しない | アーキテクチャの不一致 | `file ~/.local/bin/<tool>` で確認。ARM 環境では ARM 版バイナリを使用 |
| `Permission denied` | 実行権限がない | `chmod +x ~/.local/bin/<tool>` を再実行 |
| `wget: command not found` | wget が未インストール | `sudo apt-get install -y wget` または `curl` を代わりに使用 |
| AVX2 対応エラー（MMseqs2） | CPU が AVX2 非対応 | `mmseqs-linux-sse41.tar.gz` を使用 |
| VeryFastTree のビルド失敗 | cmake または OpenMP が未導入 | `sudo apt-get install -y cmake libomp-dev` を実行 |
| rbenv: `ruby-build` が見つからない | プラグインが未インストール | セクション 2-2 の手順を実行 |

---

## 参考リンク

| ツール | ドキュメント | ライセンス |
|--------|------------|-----------|
| datasets | https://www.ncbi.nlm.nih.gov/datasets/docs/v2/ | Public Domain |
| DIAMOND | https://github.com/bbuchfink/diamond/wiki | GPL-3.0 |
| MMseqs2 | https://github.com/soedinglab/MMseqs2/wiki | GPL-3.0 |
| SeqKit | https://bioinf.shenwei.me/seqkit/ | MIT |
| MUSCLE 5 | https://drive5.com/muscle5/manual/ | Public Domain |
| VeryFastTree | https://github.com/citiususc/veryfasttree | GPL-3.0 |
| rbenv | https://github.com/rbenv/rbenv | MIT |
