# .env.exampleファイルの自動配置について

このTerraform設定では、Difyの`.env.example`ファイルをVMに自動的に配置する機能を提供しています。

## 概要

Terraform適用時に、`docker/.env.example`ファイルをVMの`/opt/dify/`ディレクトリに自動配置します。これにより、VMにSSH接続した後、すぐに環境設定ファイルとして利用できます。

## 前提条件

`.env.example`を自動配置するには、以下の設定が必要です:

1. **SSH公開鍵**: VMへのアクセス用
2. **SSH秘密鍵**: ファイル転送のプロビジョニング用

## 設定方法

### 1. SSHキーペアの準備

既存のSSHキーを使用するか、新しく生成します:

```bash
# 新しいSSHキーペアを生成（既存のキーがある場合はスキップ）
ssh-keygen -t rsa -b 4096 -f ~/.ssh/dify_gcp_key -N ""
```

### 2. terraform.tfvarsの設定

```hcl
# SSHユーザー名（デフォルト: ubuntu）
ssh_user = "ubuntu"

# SSH公開鍵
ssh_public_key = file("~/.ssh/dify_gcp_key.pub")

# SSH秘密鍵（.env.exampleの自動配置に必要）
ssh_private_key = file("~/.ssh/dify_gcp_key")
```

### 3. デプロイ実行

```bash
terraform init
terraform apply
```

## デプロイ後の確認

VMにSSH接続して、ファイルが配置されていることを確認します:

```bash
# VMに接続
gcloud compute ssh dify-vm --zone asia-northeast1-a

# ファイルの確認
ls -la /opt/dify/.env.example
cat /opt/dify/.env.example
```

## 使用方法

VMに接続した後、配置された`.env.example`を使用してDifyをセットアップできます:

```bash
cd /opt/dify
git clone https://github.com/langgenius/dify.git
cd dify/docker

# 自動配置された.env.exampleを使用
cp /opt/dify/.env.example .env

# または、リポジトリのデフォルト設定を使用
# cp .env.example .env

# 環境変数を編集
nano .env

# Difyを起動
docker-compose up -d
```

## セキュリティに関する注意事項

### SSH秘密鍵の管理

- SSH秘密鍵は機密情報です。Terraformの状態ファイル（`terraform.tfstate`）には含まれますが、ファイルシステム上で適切な権限で保護してください
- 本番環境では、Terraform Cloud/Enterpriseのリモートバックエンドを使用し、状態ファイルを暗号化して保存することを推奨します

```bash
# ローカルの状態ファイルの権限を制限
chmod 600 terraform.tfstate terraform.tfstate.backup
```

### 代替方法

SSH秘密鍵の設定が困難な場合、以下の代替方法があります:

#### オプション1: 手動でファイルをコピー

```bash
# ローカルからVMにファイルをコピー
gcloud compute scp .env.example \
  dify-vm:/tmp/.env.example \
  --zone asia-northeast1-a

# VMに接続
gcloud compute ssh dify-vm --zone asia-northeast1-a

# ファイルを適切な場所に移動
sudo mkdir -p /opt/dify
sudo mv /tmp/.env.example /opt/dify/.env.example
sudo chown ubuntu:ubuntu /opt/dify/.env.example
```

#### オプション2: startup-scriptで配置

`startup-script.sh`にダウンロード処理を追加:

```bash
# Cloud Storageにアップロード
gsutil cp .env.example gs://your-bucket/.env.example

# startup-script.shに追加
# gsutil cp gs://your-bucket/.env.example /opt/dify/docker/.env.example
```

## トラブルシューティング

### プロビジョニングエラー

プロビジョニングに失敗した場合:

```bash
# 詳細ログを確認
terraform apply -parallelism=1

# SSH接続を手動でテスト
ssh -i ~/.ssh/dify_gcp_key ubuntu@<VM_IP>
```

### ファイル配置の確認

```bash
# VMにSSH接続
gcloud compute ssh dify-vm --zone asia-northeast1-a

# ディレクトリ構造の確認
tree /opt/dify

# ファイルの所有権とパーミッションを確認
ls -la /opt/dify/.env.example
```

### プロビジョナーの再実行

ファイルの再配置が必要な場合:

```bash
# リソースを汚染（taint）してプロビジョナーを再実行
terraform taint google_compute_instance.dify_vm
terraform apply
```

または、VMを再作成せずにプロビジョナーのみ実行:

```bash
terraform apply -replace=google_compute_instance.dify_vm
```

## 参考

- [Terraform File Provisioner](https://developer.hashicorp.com/terraform/language/resources/provisioners/file)
- [GCP SSH Keys Management](https://cloud.google.com/compute/docs/connect/add-ssh-keys)
- [Dify Docker Deployment](https://docs.dify.ai/getting-started/install-self-hosted/docker-compose)
