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

すべて `main.bicep` の `aadLogs` リソースで設定。パラメータ `enlog_Collection_enable`（旧版）→ AVM版では `main.bicep` 内で直接制御。

| ログ種別 | 取得状況 | パラメータ制御 | デフォルト |
|---|---|---|---|
| AuditLogs | 条件付き | あり | 収集する |
| SignInLogs | 条件付き | あり | 収集する |
| NonInteractiveUserSignInLogs | 条件付き | あり | 収集する |
| ServicePrincipalSignInLogs | 条件付き | あり | 収集する |
| ManagedIdentitySignInLogs | 条件付き | あり | 収集する |
| ProvisioningLogs | 条件付き | あり | 収集する |
| ADFSSignInLogs | 条件付き | あり | 収集する |
| RiskyUsers | 条件付き | あり | 収集する |
| UserRiskEvents | 条件付き | あり | 収集する |
| NetworkAccessTrafficLogs | 条件付き | あり | 収集する |
| RiskyServicePrincipals | 条件付き | あり | 収集する |
| ServicePrincipalRiskEvents | 条件付き | あり | 収集する |
| EnrichedOffice365AuditLogs | 条件付き | あり | 収集する |
| MicrosoftGraphActivityLogs | 条件付き | あり | 収集する |
| RemoteNetworkHealthLogs | 条件付き | あり | 収集する |
| NetworkAccessAlerts | 条件付き | あり | 収集する |
| NetworkAccessConnectionEvents | 条件付き | あり | 収集する |
| MicrosoftServicePrincipalSignInLogs | 条件付き | あり | 収集する |
| AzureADGraphActivityLogs | 条件付き | あり | 収集する |

> Entra ID ログの収集にはテナントレベルの**セキュリティ管理者**ロールが必要です。

## サブスクリプション アクティビティログ

すべて `main.bicep` の `diagnosticLogs_active` リソースで設定。

| ログ種別 | 取得状況 | パラメータ制御 | デフォルト |
|---|---|---|---|
| Administrative | 条件付き | あり | 収集する |
| Security | 条件付き | あり | 収集する |
| ServiceHealth | 条件付き | あり | 収集する |
| Alert | 条件付き | あり | 収集する |
| Recommendation | 条件付き | あり | 収集する |
| Policy | 条件付き | あり | 収集する |
| Autoscale | 条件付き | あり | 収集する |
| ResourceHealth | 条件付き | あり | 収集する |

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
| Azure OpenAI Request Usage | **未取得** | 要手動設定 |
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
