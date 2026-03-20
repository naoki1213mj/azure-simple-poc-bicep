# コスト見積もりガイド   <!-- omit in toc -->

本テンプレートでデプロイされる環境の月額概算コストです。  
料金は **Japan East リージョン**、**従量課金**を前提としています。

> **注意**: 料金は 2026年3月時点の概算です。最新の正確な料金は [Azure 料金計算ツール](https://azure.microsoft.com/pricing/calculator/) で確認してください。為替レートにより変動します。

## 目次   <!-- omit in toc -->

- [dev 環境（最小構成）](#dev-環境最小構成)
- [prod 環境（フル構成）](#prod-環境フル構成)
- [コスト削減のヒント](#コスト削減のヒント)
- [リソース別の料金参考リンク](#リソース別の料金参考リンク)

## dev 環境（最小構成）

**構成**: CPU VM x1 / GPU VM なし / Application Gateway なし / Backup なし

| カテゴリ | リソース | SKU / 仕様 | 月額概算 (USD) | 備考 |
|---|---|---|---|---|
| **コンピュート** | CPU VM x1 | Standard_D4as_v5 (4vCPU/16GB) | ~$125 | 自動停止で圧縮可 |
| | OS ディスク | StandardSSD 128GB | ~$10 | |
| | データディスク | StandardSSD 256GB | ~$20 | |
| **ネットワーク** | Azure Bastion | Standard SKU (2 units) | ~$274 | 固定費が大きい |
| | Public IP (Bastion) | Standard Static | ~$4 | |
| | NAT Gateway | Standard | ~$32 | |
| | Public IP (NAT) | Standard Static | ~$4 | |
| | VNet / NSG / Peering | - | 無料 | |
| **セキュリティ** | Key Vault | Standard | ~$0.03/操作 | ほぼ無料 |
| | Private DNS Zone x3 | - | ~$1.50 | $0.50/zone |
| | Private Endpoint x1 | Storage Blob | ~$7 | |
| **監視** | Log Analytics | PerGB2018 (5GB/月想定) | ~$14 | データ量依存 |
| **AI** | AI Services | S0 | 無料 (基本料) | API呼び出し従量 |
| | モデルデプロイ (gpt-5.4-mini) | GlobalStandard 10K TPM | ~$0.15/1M入力トークン | 使用量依存 |
| **ストレージ** | Storage Account | Standard LRS | ~$2 | ログ容量依存 |
| | | | | |
| **合計（概算）** | | | **~$490/月** | |

### dev 環境のコスト内訳

```
コンピュート ████████████████░░░░░░░░░ 32%  (~$155)
ネットワーク ████████████████████████░ 65%  (~$314)  ← Bastion が支配的
その他       ██░░░░░░░░░░░░░░░░░░░░░░  3%  (~$25)
```

> **ポイント**: dev 環境のコストの約 56% は Azure Bastion です。VM 自動停止を有効にしても、Bastion は常時課金されます。

## prod 環境（フル構成）

**構成**: CPU VM x1 + GPU VM x1 / Application Gateway (WAF v2) / Backup あり / 全監視有効

| カテゴリ | リソース | SKU / 仕様 | 月額概算 (USD) | 備考 |
|---|---|---|---|---|
| **コンピュート** | CPU VM x1 | Standard_D8as_v5 (8vCPU/32GB) | ~$250 | |
| | GPU VM x1 | Standard_NC24ads_A100_v4 (24vCPU/220GB/A100) | ~$5,420 | **最大コスト** |
| | OS ディスク (CPU) | StandardSSD 128GB | ~$10 | |
| | OS ディスク (GPU) | StandardSSD 1536GB | ~$122 | |
| | データディスク (CPU) | StandardSSD 512GB | ~$38 | |
| | データディスク (GPU) | StandardSSD 1536GB | ~$122 | |
| **ネットワーク** | Azure Bastion | Standard SKU (2 units) | ~$274 | |
| | Application Gateway | WAF_v2 (1 unit) | ~$327 | capacity=1 |
| | Public IP (Bastion) | Standard Static | ~$4 | |
| | Public IP (AGW) | Standard Static | ~$4 | |
| | NAT Gateway | Standard | ~$32 | |
| | Public IP (NAT) | Standard Static | ~$4 | |
| **セキュリティ** | Key Vault | Standard | ~$1 | |
| | Defender for Cloud (VM) | P1 (2 VM) | ~$15/VM = $30 | |
| | Private DNS Zone x3 | - | ~$1.50 | |
| | Private Endpoint x3 | Storage + KV + AI | ~$21 | |
| **監視** | Log Analytics | PerGB2018 (20GB/月想定) | ~$55 | |
| | Azure Monitor (DCR/AMA) | - | ~$5 | |
| **AI** | AI Services | S0 | 無料 (基本料) | |
| | モデルデプロイ (gpt-5 等 x3) | GlobalStandard | 使用量依存 | ~$0.005/1K トークン |
| **バックアップ** | Recovery Services Vault | GRS (2 VM) | ~$20 | 保護データ量依存 |
| **ストレージ** | Storage Account | Standard LRS | ~$5 | |
| **自動化** | VM 自動停止 (DevTestLab Schedule) | - | 無料 | |
| | | | | |
| **合計（概算）** | | | **~$6,750/月** | |

### prod 環境のコスト内訳

```
GPU VM       ████████████████████████░ 80%  (~$5,420)  ← 圧倒的
CPU VM       ██░░░░░░░░░░░░░░░░░░░░░░  4%  (~$250)
AGW+Bastion  ████░░░░░░░░░░░░░░░░░░░░  9%  (~$600)
ディスク     ██░░░░░░░░░░░░░░░░░░░░░░  4%  (~$292)
その他       █░░░░░░░░░░░░░░░░░░░░░░░  3%  (~$188)
```

> **ポイント**: prod 環境のコストの約 80% は GPU VM (A100) です。GPU 不要な時間帯は自動停止を設定するか、必要時のみ手動起動を検討してください。

## コスト削減のヒント

### 即効性のある施策

| 施策 | 削減効果 | 方法 |
|---|---|---|
| **VM 自動停止** | GPU VM: 最大 ~67% | `enableVmAutoStartStop = true` + 業務時間のみ稼働 (10h/24h) |
| **GPU VM SKU 変更** | ~$4,000/月 | `Standard_NC4as_T4_v3` (~$380/月) に変更 |
| **Bastion 削除** | ~$274/月 | 必要時のみデプロイ（スクリプト化） |
| **Reserved Instance (1年)** | ~30-40% | CPU VM / GPU VM に RI 適用 |
| **Reserved Instance (3年)** | ~50-60% | 長期利用が確定している場合 |

### 構成による削減

| 構成変更 | dev 月額 | prod 月額 |
|---|---|---|
| 現状 | ~$490 | ~$6,750 |
| VM 自動停止 (10h/日, 平日のみ) | ~$430 | ~$3,200 |
| GPU → T4 + 自動停止 | - | ~$1,500 |
| Bastion を必要時のみ | ~$220 | ~$6,480 |
| RI 1年 (VM) | ~$350 | ~$4,700 |

### Azure Pricing Calculator で正確な見積もりを作成

1. [Azure 料金計算ツール](https://azure.microsoft.com/pricing/calculator/) にアクセス
2. 上記の各リソースを追加
3. リージョン「Japan East」を選択
4. SKU・数量を環境に合わせて設定
5. 見積もりを保存・共有

## リソース別の料金参考リンク

| リソース | 料金ページ |
|---|---|
| Virtual Machines | [料金](https://azure.microsoft.com/pricing/details/virtual-machines/linux/) |
| Azure Bastion | [料金](https://azure.microsoft.com/pricing/details/azure-bastion/) |
| Application Gateway | [料金](https://azure.microsoft.com/pricing/details/application-gateway/) |
| NAT Gateway | [料金](https://azure.microsoft.com/pricing/details/azure-nat-gateway/) |
| Key Vault | [料金](https://azure.microsoft.com/pricing/details/key-vault/) |
| Storage Account | [料金](https://azure.microsoft.com/pricing/details/storage/blobs/) |
| Log Analytics | [料金](https://azure.microsoft.com/pricing/details/monitor/) |
| AI Services | [料金](https://azure.microsoft.com/pricing/details/cognitive-services/openai-service/) |
| Recovery Services | [料金](https://azure.microsoft.com/pricing/details/backup/) |
| Defender for Cloud | [料金](https://azure.microsoft.com/pricing/details/defender-for-cloud/) |
| Private Endpoint | [料金](https://azure.microsoft.com/pricing/details/private-link/) |
