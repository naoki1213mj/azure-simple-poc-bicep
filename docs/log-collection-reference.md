# ログ収集一覧   <!-- omit in toc -->

本テンプレートでデプロイされる環境で収集可能なログの一覧です。  
各ログの取得状況、制御パラメータ、設定箇所をまとめています。

## 目次   <!-- omit in toc -->

- [概要](#概要)
- [ネットワーク](#ネットワーク)
- [仮想マシン (VM)](#仮想マシン-vm)
- [Entra ID（旧 Azure AD）](#entra-id旧-azure-ad)
- [サブスクリプション アクティビティログ](#サブスクリプション-アクティビティログ)
- [ストレージアカウント](#ストレージアカウント)
- [Key Vault](#key-vault)
- [AI Services（Foundry）](#ai-servicesfoundry)
- [ログ取得状況の凡例](#ログ取得状況の凡例)

## 概要

| 収集先 | 説明 |
|---|---|
| **Log Analytics Workspace** | 全ログの集約先。クエリ・アラートに使用 |
| **Storage Account** | ログのエクスポート先（長期保持用） |
| **VNet Flow Log** | ネットワークトラフィックの記録 |

## ネットワーク

| ログ種別 | 取得状況 | パラメータ制御 | パラメータ名 | デフォルト | 設定箇所 |
|---|---|---|---|---|---|
| VNet Flow Log (Hub) | 常に取得 | なし | - | - | `scripts/postprovision.sh` |
| VNet Flow Log (Spoke) | 常に取得 | なし | - | - | `scripts/postprovision.sh` |
| Traffic Analytics | 常に取得 | なし | - | - | `scripts/postprovision.sh` |
| Hub VNet 診断ログ | 常に取得 | なし | - | - | `infra/modules/hub.bicep` (AVM diagnosticSettings) |
| Spoke VNet 診断ログ | 常に取得 | なし | - | - | `infra/modules/spoke.bicep` (AVM diagnosticSettings) |
| Bastion 診断ログ | 常に取得 | なし | - | - | `infra/modules/hub.bicep` (AVM diagnosticSettings) |
| NSG 診断ログ (Bastion/AGW/VM/PEP) | 常に取得 | なし | - | - | `infra/modules/hub.bicep`, `spoke.bicep` (AVM diagnosticSettings) |
| AGW アクセスログ | 条件付き | あり | `enableAppGateway` | `false` | `infra/modules/hub.bicep` (AVM diagnosticSettings) |
| AGW パフォーマンスログ | 条件付き | あり | `enableAppGateway` | `false` | `infra/modules/hub.bicep` (AVM diagnosticSettings) |
| AGW WAF ログ | 条件付き | あり | `enableAppGateway` | `false` | `infra/modules/hub.bicep` (AVM diagnosticSettings) |
| NSG フローログ | **未取得** | - | - | - | 要手動設定 ※1 |

> ※1 NSG フローログは VNet Flow Log で代替可能です。個別の NSG フローログが必要な場合は `az network watcher flow-log create` で追加してください。

## 仮想マシン (VM)

| ログ種別 | 取得状況 | パラメータ制御 | パラメータ名 | デフォルト | 設定箇所 |
|---|---|---|---|---|---|
| VM パフォーマンス (CPU/Mem/Disk) | 条件付き | あり | `enableVmMonitoring` | `false` | `infra/modules/spoke.bicep` (AVM diagnosticSettings) |
| VM ブート診断 | 常に取得 | なし | - | - | `infra/modules/spoke.bicep` (bootDiagnostics) |
| Syslog | 条件付き | あり | `enableVmMonitoring` | `false` | `infra/modules/spoke.bicep` (DCR) |
| セキュリティイベント | **未取得** | - | - | - | 要 Defender for Cloud ※2 |
| カスタムログ | **未取得** | - | - | - | 要手動設定 |
| プロセス実行ログ | **未取得** | - | - | - | 要手動設定 |

> ※2 `enableDefender = true` で Microsoft Defender for Cloud を有効化すると、セキュリティイベントが自動収集されます。

## Entra ID（旧 Azure AD）

現在のテンプレートでは Entra ID ログの自動収集は実装されていません。必要な場合はテナントレベルの診断設定を手動で追加してください。

```bash
# Entra ID ログを Log Analytics に転送（テナントのセキュリティ管理者ロールが必要）
az monitor diagnostic-settings create \
  --name "entra-to-law" \
  --resource "/providers/Microsoft.aadiam/diagnosticSettings" \
  --workspace "<Log Analytics Workspace ID>" \
  --logs '[{"category":"AuditLogs","enabled":true},{"category":"SignInLogs","enabled":true}]'
```

> Entra ID ログの収集にはテナントレベルの**セキュリティ管理者**ロールが必要です。

## サブスクリプション アクティビティログ

`main.bicep` の `activityLogDiag` リソースで設定。常に Log Analytics に転送されます。

| ログ種別 | 取得状況 | 備考 |
|---|---|---|
| Administrative | 常に取得 | |
| Security | 常に取得 | |
| Alert | 常に取得 | |
| Policy | 常に取得 | |
| ServiceHealth | **未取得** | 必要な場合は diagnosticSettings に追加 |
| Recommendation | **未取得** | 必要な場合は diagnosticSettings に追加 |
| Autoscale | **未取得** | 必要な場合は diagnosticSettings に追加 |
| ResourceHealth | **未取得** | 必要な場合は diagnosticSettings に追加 |

## ストレージアカウント

| ログ種別 | 取得状況 | 備考 |
|---|---|---|
| Blob 監査ログ | **未取得** | AVM の diagnosticSettings で追加可能 |

> ストレージアカウントのログが必要な場合は、AVM モジュールの `diagnosticSettings` パラメータに Blob の診断設定を追加してください。

## Key Vault

| ログ種別 | 取得状況 | 備考 |
|---|---|---|
| AuditEvent | 常に取得 | AVM の diagnosticSettings で自動設定 |
| Azure Policy Evaluation Details | 常に取得 | AVM の diagnosticSettings で自動設定 |

## AI Services（Foundry）

| ログ種別 | 取得状況 | 備考 |
|---|---|---|
| Audit Logs | 条件付き | AVM の diagnosticSettings で設定（`enableFoundry = true` 時） |
| Request and Response Logs | **未取得** | 要手動設定 |
| AI Services Request Usage | **未取得** | 要手動設定 |
| Trace Logs | **未取得** | 要手動設定 |

> AI Services の詳細ログ（リクエスト/レスポンス、使用量、トレース）が必要な場合は、Azure Portal または CLI で個別に診断設定を追加してください。
>
> ```bash
> az monitor diagnostic-settings create \
>   --name "diag-ais" \
>   --resource "<AI Services リソース ID>" \
>   --workspace "<Log Analytics Workspace ID>" \
>   --logs '[{"category":"RequestResponse","enabled":true},{"category":"Audit","enabled":true}]'
> ```

## ログ取得状況の凡例

| 表記 | 意味 |
|---|---|
| **常に取得** | テンプレートデプロイ時に自動で収集開始。パラメータによる無効化不可 |
| **条件付き** | パラメータで有効/無効を制御可能 |
| **未取得** | テンプレートでは設定されない。必要な場合は手動で追加 |
