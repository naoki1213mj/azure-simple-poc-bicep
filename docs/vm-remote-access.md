# VM リモート接続ガイド   <!-- omit in toc -->

Azure Bastion 経由で PoC 環境の VM にリモート接続する方法をまとめています。  
SSH 接続、ポートフォワーディング（トンネリング）、Jupyter Notebook / marimo の利用方法を説明します。

## 目次   <!-- omit in toc -->

- [前提条件](#前提条件)
- [1. Bastion トンネルの確立](#1-bastion-トンネルの確立)
- [2. SSH 接続](#2-ssh-接続)
- [3. ポートフォワーディング（トンネリング）](#3-ポートフォワーディングトンネリング)
- [4. VS Code Remote SSH 接続](#4-vs-code-remote-ssh-接続)
- [5. Jupyter Notebook のセットアップ](#5-jupyter-notebook-のセットアップ)
- [6. marimo のセットアップ](#6-marimo-のセットアップ)
- [7. 複数ポートの同時転送](#7-複数ポートの同時転送)
- [8. トラブルシューティング](#8-トラブルシューティング)

## 前提条件

- Azure CLI と拡張機能がインストール済みであること
  ```bash
  az extension add --name bastion
  az extension add --name ssh
  ```
- VM の SSH 秘密鍵を手元に持っていること
- Azure にログイン済みであること
  ```bash
  az login
  az account set --subscription "<サブスクリプション ID>"
  ```

## 1. Bastion トンネルの確立

すべての接続方法の土台となる Bastion トンネルを確立します。

```bash
# 変数の設定
PREFIX="<prefix>"
LOCATION="japaneast"
VM_NAME="vm-cpu-${PREFIX}-${LOCATION}-001"  # または vm-gpu-...
HUB_RG="rg-hub-${PREFIX}-${LOCATION}-001"
SPOKE_RG="rg-spoke-${PREFIX}-${LOCATION}-001"
BASTION_NAME="bas-${PREFIX}-${LOCATION}-001"
LOCAL_PORT=50022  # ローカルで使用するポート

# VM のリソース ID を取得
VM_ID=$(az vm show \
  --resource-group "$SPOKE_RG" \
  --name "$VM_NAME" \
  --query id -o tsv)

# Bastion トンネルを確立
az network bastion tunnel \
  --name "$BASTION_NAME" \
  --resource-group "$HUB_RG" \
  --target-resource-id "$VM_ID" \
  --resource-port 22 \
  --port $LOCAL_PORT
```

以下が表示されれば接続成功です:
```
Opening tunnel on port: 50022
Tunnel is ready, connect on port 50022
Ctrl + C to close
```

> **重要**: このターミナルは開いたまま維持してください。以降の操作はすべて**別のターミナル**で行います。

## 2. SSH 接続

### 基本的な SSH 接続

```bash
ssh -p 50022 -i "<秘密鍵パス>" azureuser@127.0.0.1
```

### SSH 設定ファイルによる簡略化

`~/.ssh/config` に以下を追加すると、毎回引数を指定する必要がなくなります:

```
Host azure-vm
    HostName 127.0.0.1
    Port 50022
    User azureuser
    IdentityFile ~/.ssh/id_rsa_azure
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
```

以降は `ssh azure-vm` だけで接続できます。

## 3. ポートフォワーディング（トンネリング）

VM 上で動作する Web アプリケーション（Jupyter, marimo 等）にローカルブラウザからアクセスするための設定です。

### 単一ポート転送

```bash
# VM の 8888 番ポートをローカルの 8888 番に転送
ssh -p 50022 -i "<秘密鍵パス>" \
  -L 8888:localhost:8888 \
  azureuser@127.0.0.1
```

### SSH 設定ファイル使用時

```bash
ssh -L 8888:localhost:8888 azure-vm
```

転送後、ローカルブラウザで `http://localhost:8888` にアクセスできます。

## 4. VS Code Remote SSH 接続

VS Code から直接 VM に接続して開発できます。

### セットアップ

1. VS Code に **Remote - SSH** 拡張機能をインストール
2. `~/.ssh/config` に [SSH設定](#ssh-設定ファイルによる簡略化) を追加（上記参照）
3. Bastion トンネルを確立（[手順1](#1-bastion-トンネルの確立)）

### 接続

1. VS Code のコマンドパレット（`Cmd+Shift+P` / `Ctrl+Shift+P`）を開く
2. `Remote-SSH: Connect to Host...` を選択
3. `azure-vm` を選択
4. 接続後、VM 上のファイルを直接編集・ターミナル操作が可能

### ポートフォワーディング（VS Code 内蔵）

VS Code 接続中は、VS Code の **PORTS** パネルからポート転送を GUI で追加できます:
1. 下部パネルの「**PORTS**」タブを開く
2. 「**Forward a Port**」をクリック
3. ポート番号（例: `8888`）を入力

## 5. Jupyter Notebook のセットアップ

### VM 上での uv + Jupyter インストール

```bash
# SSH 接続 + ポート転送
ssh -p 50022 -i "<秘密鍵パス>" \
  -L 8888:localhost:8888 \
  azureuser@127.0.0.1

# VM 上で実行: uv のインストール
curl -LsSf https://astral.sh/uv/install.sh | sh
source $HOME/.local/bin/env

# プロジェクトディレクトリを作成
mkdir -p ~/workspace && cd ~/workspace
uv init --python 3.12

# Jupyter をインストール
uv add jupyter

# Jupyter Notebook を起動
uv run jupyter notebook --no-browser --ip=127.0.0.1 --port=8888
```

起動後に表示される URL（`http://127.0.0.1:8888/?token=...`）をローカルブラウザで開きます。

### JupyterLab を使う場合

```bash
uv add jupyterlab

uv run jupyter lab --no-browser --ip=127.0.0.1 --port=8888
```

### GPU VM での PyTorch/CUDA 確認

```bash
# PyTorch をインストール（CUDA 12.4 対応）
uv add torch torchvision --index-url https://download.pytorch.org/whl/cu124
```

Jupyter / marimo 上で確認:

```python
import torch
print(f"CUDA available: {torch.cuda.is_available()}")
print(f"GPU count: {torch.cuda.device_count()}")
print(f"GPU name: {torch.cuda.get_device_name(0)}")
```

### パスワード設定（オプション）

```bash
# トークンの代わりにパスワードを設定
uv run jupyter notebook password
# パスワードを入力

# パスワード認証で起動
uv run jupyter notebook --no-browser --ip=127.0.0.1 --port=8888
```

## 6. marimo のセットアップ

[marimo](https://marimo.io/) は Python のリアクティブノートブックです。Git フレンドリーな `.py` ファイルとして保存されます。

### VM 上での uv + marimo インストール

```bash
# SSH 接続 + ポート転送
ssh -p 50022 -i "<秘密鍵パス>" \
  -L 2718:localhost:2718 \
  azureuser@127.0.0.1

# VM 上で実行: uv が未インストールの場合
curl -LsSf https://astral.sh/uv/install.sh | sh
source $HOME/.local/bin/env

# プロジェクトがない場合は作成
mkdir -p ~/workspace && cd ~/workspace
uv init --python 3.12

# marimo をインストール
uv add marimo

# marimo エディタを起動
uv run marimo edit --host 127.0.0.1 --port 2718 --no-token
```

ローカルブラウザで `http://localhost:2718` にアクセスします。

### 既存のノートブックを開く

```bash
# 新規作成
uv run marimo edit my_notebook.py --host 127.0.0.1 --port 2718

# 既存ファイルを開く
uv run marimo edit /path/to/existing.py --host 127.0.0.1 --port 2718
```

### Jupyter ノートブックからの変換

```bash
# .ipynb → .py (marimo形式) に変換
uv run marimo convert notebook.ipynb > notebook.py

# 変換したファイルを開く
uv run marimo edit notebook.py --host 127.0.0.1 --port 2718
```

### uv tool でグローバルインストール（プロジェクト不要）

プロジェクトを作らずにサクッと使いたい場合:

```bash
# marimo をグローバルツールとしてインストール
uv tool install marimo

# そのまま起動
marimo edit --host 127.0.0.1 --port 2718 --no-token

# または uvx で一時的に実行（インストール不要）
uvx marimo edit --host 127.0.0.1 --port 2718 --no-token
```

## 7. 複数ポートの同時転送

複数の Web サービスを同時に使う場合:

```bash
# Jupyter (8888) + marimo (2718) + カスタムアプリ (8080) を同時転送
ssh -p 50022 -i "<秘密鍵パス>" \
  -L 8888:localhost:8888 \
  -L 2718:localhost:2718 \
  -L 8080:localhost:8080 \
  azureuser@127.0.0.1
```

または SSH 設定ファイルに追記:

```
Host azure-vm
    HostName 127.0.0.1
    Port 50022
    User azureuser
    IdentityFile ~/.ssh/id_rsa_azure
    LocalForward 8888 localhost:8888
    LocalForward 2718 localhost:2718
    LocalForward 8080 localhost:8080
```

## 8. トラブルシューティング

### Bastion トンネルが切断される

```bash
# ServerAliveInterval を設定して接続を維持
ssh -p 50022 -i "<秘密鍵パス>" \
  -o ServerAliveInterval=60 \
  -o ServerAliveCountMax=3 \
  azureuser@127.0.0.1
```

SSH 設定ファイルに追加する場合:
```
Host azure-vm
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

### ポートが既に使用されている

```bash
# 使用中のポートを確認
lsof -i :8888

# 別のローカルポートを使用
ssh -p 50022 -i "<秘密鍵パス>" \
  -L 9999:localhost:8888 \
  azureuser@127.0.0.1
# → http://localhost:9999 でアクセス
```

### Jupyter が外部からアクセスできない

```bash
# VM 上で確認
jupyter notebook list

# 127.0.0.1 でリッスンしているか確認
ss -tlnp | grep 8888
```

### Bastion トンネルのポートを変更したい

```bash
# デフォルトの 50022 が使えない場合、別のポートを使用
az network bastion tunnel \
  --name "$BASTION_NAME" \
  --resource-group "$HUB_RG" \
  --target-resource-id "$VM_ID" \
  --resource-port 22 \
  --port 60022  # 任意の空きポート
```
