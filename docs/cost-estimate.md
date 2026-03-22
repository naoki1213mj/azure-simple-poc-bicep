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
| **コンピュート** | CPU VM x1 | Standard_D4s_v6 (4vCPU/16GB) | ~$140 | 自動停止で圧縮可 |
| | OS ディスク | StandardSSD 128GB | ~$10 | |
| | データディスク | StandardSSD 256GB | ~$20 | |
| **ネットワーク** | Azure Bastion | Standard SKU (2 units) | ~$274 | 固定費が大きい |
| | Public IP (Bastion) | Standard Static | ~$4 | |
| | NAT Gateway | Standard | ~$32 | |
| | Public IP (NAT) | Standard Static | ~$4 | |
| | VNet / NSG / Peering | - | 無料 | |
| **セキュリティ** | Key Vault | Standard | ~$0.03/操作 | ほぼ無料 |
| | Private DNS Zone x3 | - | ~$1.50 | $0.50/zone |
| **監視** | Log Analytics | PerGB2018 (5GB/月想定) | ~$14 | データ量依存 |
| **AI** | AI Services | S0 | 無料 (基本料) | API呼び出し従量 |
| | モデルデプロイ (gpt-5-mini) | GlobalStandard 10K TPM | ~$0.15/1M入力トークン | 使用量依存 |
| | Private Endpoint (AI Services) | - | ~$7 | |
| **ストレージ** | Storage Account | Standard LRS | ~$2 | ログ容量依存 |
| | Private Endpoint (Blob) | - | ~$7 | |
| | | | | |
| **合計（概算）** | | | **~$510/月** | |

### dev 環境のコスト内訳

```
コンピュート ████████████████░░░░░░░░░ 33%  (~$170)
ネットワーク ████████████████████████░ 62%  (~$314)  ← Bastion が支配的
その他       ██░░░░░░░░░░░░░░░░░░░░░░  5%  (~$30)
```

> **ポイント**: dev 環境のコストの約 54% は Azure Bastion です。VM 自動停止を有効にしても、Bastion は常時課金されます。

## prod 環境（フル構成）

**構成**: CPU VM x1 / GPU VM なし / Application Gateway (WAF v2) / Backup あり / Defender 有効 / 全監視有効

> **注意**: 現在の `prod.bicepparam` は GPU VM を無効 (`vmPattern = 1`, `gpuvmNumber = 0`) にしています。GPU VM を追加する場合は別途コストが加算されます。

| カテゴリ | リソース | SKU / 仕様 | 月額概算 (USD) | 備考 |
|---|---|---|---|---|
| **コンピュート** | CPU VM x1 | Standard_D8s_v6 (8vCPU/32GB) | ~$280 | |
| | OS ディスク (CPU) | StandardSSD 128GB | ~$10 | |
| | データディスク (CPU) | StandardSSD 512GB | ~$38 | |
| **ネットワーク** | Azure Bastion | Standard SKU (2 units) | ~$274 | |
| | Application Gateway | WAF_v2 (1 unit) | ~$327 | capacity=1 |
| | Public IP (Bastion) | Standard Static | ~$4 | |
| | Public IP (AGW) | Standard Static | ~$4 | |
| | NAT Gateway | Standard | ~$32 | |
| | Public IP (NAT) | Standard Static | ~$4 | |
| **セキュリティ** | Key Vault | Standard | ~$1 | |
| | Defender for Cloud (VM) | P1 (1 VM) | ~$15 | |
| | Private DNS Zone x3 | - | ~$1.50 | |
| **監視** | Log Analytics | PerGB2018 (20GB/月想定) | ~$55 | |
| | Azure Monitor (DCR/AMA) | - | ~$5 | |
| **AI** | AI Services | S0 | 無料 (基本料) | |
| | モデルデプロイ (gpt-5 等 x2) | GlobalStandard | 使用量依存 | ~$0.005/1K トークン |
| | Private Endpoint (AI Services) | - | ~$7 | |
| **バックアップ** | Recovery Services Vault | GRS (1 VM) | ~$10 | 保護データ量依存 |
| **ストレージ** | Storage Account | Standard LRS | ~$5 | |
| | Private Endpoint (Blob) | - | ~$7 | |
| **不変性** | WORM ポリシー | 30日保持 | 無料 (ポリシー自体) | ストレージ料金に含む |
| | | | | |
| **合計（概算）** | | | **~$1,080/月** | |

### prod 環境のコスト内訳

```
AGW+Bastion  ████████████████████████░ 56%  (~$609)  ← ネットワーク系が支配的
CPU VM       ██████████░░░░░░░░░░░░░░░ 26%  (~$280)
ディスク     ███░░░░░░░░░░░░░░░░░░░░░░  4%  (~$48)
監視         ████░░░░░░░░░░░░░░░░░░░░░  6%  (~$60)
その他       ██░░░░░░░░░░░░░░░░░░░░░░░  8%  (~$83)
```

> **ポイント**: GPU VM を追加する場合（例: `Standard_NC24ads_A100_v4`）、月額 ~$5,420 が加算され合計 ~$6,500/月 になります。

## コスト削減のヒント

### 即効性のある施策

| 施策 | 削減効果 | 方法 |
|---|---|---|
| **VM 自動停止** | CPU VM: 最大 ~67% | `enableVmAutoStartStop = true` + 業務時間のみ稼働 (10h/24h) |
| **Bastion 削除** | ~$274/月 | 必要時のみデプロイ（スクリプト化） |
| **Reserved Instance (1年)** | ~30-40% | CPU VM に RI 適用 |
| **Reserved Instance (3年)** | ~50-60% | 長期利用が確定している場合 |

### 構成による削減

| 構成変更 | dev 月額 | prod 月額 |
|---|---|---|
| 現状 | ~$510 | ~$1,080 |
| VM 自動停止 (10h/日, 平日のみ) | ~$450 | ~$1,000 |
| Bastion を必要時のみ | ~$240 | ~$810 |
| RI 1年 (VM) | ~$370 | ~$830 |

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
