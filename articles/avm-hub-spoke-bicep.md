---
title: "AVM + Bicep で Azure Hub-Spoke 環境を一撃デプロイする"
emoji: "🏗️"
type: "tech"
topics: ["azure", "bicep", "avm", "infrastructure"]
published: false
---

## この記事の動機

Azure でエンタープライズ向けの検証環境を立ち上げるたびに、手作業とポータル操作が増えていく。VNet を作って、サブネットを切って、NSG を書いて、Bastion を置いて……。毎回やると半日かかるし、設定ミスが怖い。

この課題を Bicep と Azure Verified Modules（AVM）で解決した。サブスクリプションスコープの `main.bicep` 一発で Hub-Spoke 構成が丸ごと立ち上がる。実際に動いたテンプレートを公開しながら、設計判断とハマりどころを残しておく。

## 何ができるテンプレートか

1コマンドで以下の構成がデプロイされる。

- Hub VNet（Bastion、Private DNS Zone、Application Gateway + WAF v2）
- Spoke VNet（CPU / GPU VM、Key Vault、Storage Account、AI Services）
- Hub ↔ Spoke の双方向 VNet Peering
- Private Endpoint 経由での AI Services・Storage・Key Vault 接続
- Log Analytics への診断ログ集約
- VM 自動停止スケジュール、Recovery Services Vault（オプション）

dev 環境は CPU VM 1 台＋最小構成、prod は GPU VM 追加＋ WAF 有効＋ Defender＋バックアップのフル構成、といった切り替えを `.bicepparam` だけで制御する。

## アーキテクチャ図

```
Hub VNet (10.0.0.0/16)
├── AzureBastionSubnet  (10.0.0.0/26)  ─ Bastion Host (Standard)
├── snet-agw            (10.0.1.0/24)  ─ Application Gateway + WAF v2 [prod のみ]
│
Spoke VNet (10.1.0.0/16)
├── snet-vm             (10.1.0.0/24)  ─ CPU/GPU VM + NAT Gateway
├── snet-pep            (10.1.1.0/24)  ─ Private Endpoint (Storage, AI Services, Key Vault)
│
共有サービス
├── Log Analytics ── 全リソースの診断ログ
├── Key Vault ── シークレット管理 (RBAC 認可)
├── Storage Account ── Blob (PE 経由のみ接続)
├── AI Services ── GPT モデル (PE 経由のみ接続)
└── Private DNS Zones ── blob / cognitiveservices / vaultcore
```

Hub に Private DNS Zone を集約して Spoke VNet にリンクする構成を取った。Spoke 側のリソースが PE を使うとき、Hub の DNS Zone 経由で名前解決される。PE の DNS 設定を Hub に寄せることで、Spoke が増えても DNS Zone の管理は 1 箇所で済む。

## AVM を選んだ理由

旧 ALZ-Bicep は 2026 年 2 月にアーカイブ済みで、Microsoft が公式に推奨しているのは AVM に移行した。AVM のモジュールは Public Bicep Registry（`br/public:avm/res/...`）から直接参照でき、`bicep restore` で自動的にキャッシュされる。

実際に使ったモジュールはこんな感じ。

| モジュール | バージョン | 用途 |
|-----------|-----------|------|
| `avm/res/network/virtual-network` | 0.5.2 | Hub / Spoke VNet |
| `avm/res/network/network-security-group` | 0.5.0 | サブネット NSG |
| `avm/res/network/bastion-host` | 0.6.0 | Bastion |
| `avm/res/network/private-dns-zone` | 0.7.0 | PE 用 Private DNS |
| `avm/res/network/nat-gateway` | 1.2.1 | Spoke NAT Gateway |
| `avm/res/operational-insights/workspace` | 0.9.1 | Log Analytics |
| `avm/res/key-vault/vault` | 0.11.0 | Key Vault |
| `avm/res/storage/storage-account` | 0.15.0 | Storage Account |
| `avm/res/cognitive-services/account` | 0.10.0 | AI Services |
| `avm/res/compute/virtual-machine` | 0.12.0 | CPU / GPU VM |
| `avm/res/recovery-services/vault` | 0.12.0 | バックアップ |

Application Gateway だけは AVM モジュールのパラメータ構造が独特で、今回は `resource` 直書きにした。WAF Policy も同様。この判断は後述する。

## テンプレート構成

```
infra/
├── main.bicep              ← サブスクリプションスコープのエントリポイント
├── bicepconfig.json
├── modules/
│   ├── hub.bicep           ← Hub VNet + Bastion + AppGW + DNS Zone
│   ├── spoke.bicep         ← Spoke VNet + VM + KV + Storage + AI
│   ├── peering.bicep       ← Hub→Spoke Peering + Spoke→Hub 呼び出し
│   ├── spoke-peering.bicep ← Spoke RG スコープの Peering リソース
│   └── cloud-init/
│       ├── cpu-vm.yaml
│       └── gpu-vm.yaml
└── parameters/
    ├── dev.bicepparam       ← 最小構成
    └── prod.bicepparam      ← フル構成
```

`main.bicep` がサブスクリプションスコープで、リソースグループの作成からモジュール呼び出しまで一括管理する。

```bicep:infra/main.bicep
targetScope = 'subscription'

// リソースグループ
resource hubRg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: hubRgName
  location: location
  tags: tags
}

resource spokeRg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: spokeRgName
  location: location
  tags: tags
}

// Hub → Spoke → Peering の順でデプロイ
module hub 'modules/hub.bicep' = {
  name: 'deploy-hub'
  scope: hubRg
  params: { /* 省略 */ }
}

module spoke 'modules/spoke.bicep' = {
  name: 'deploy-spoke'
  scope: spokeRg
  params: {
    // Hub の DNS Zone ID を渡す
    hubDnsZoneBlobId: hub.outputs.dnsZoneBlobId
    hubDnsZoneCogServicesId: hub.outputs.dnsZoneCogServicesId
    hubDnsZoneVaultId: hub.outputs.dnsZoneVaultId
    /* 他は省略 */
  }
}

module peering 'modules/peering.bicep' = {
  name: 'deploy-peering'
  scope: hubRg
  params: {
    hubVnetName: hub.outputs.vnetName
    hubVnetId: hub.outputs.vnetId
    spokeVnetName: spoke.outputs.vnetName
    spokeVnetId: spoke.outputs.vnetId
    spokeRgName: spokeRgName
  }
}
```

記事用に簡略化しているが、実際のパラメータは [infra/main.bicep](https://github.com) を参照してほしい。

## Hub モジュールの設計

Hub には 3 つの役割がある。Bastion によるセキュアな VM アクセス、Private DNS Zone の集約、Application Gateway での L7 保護。

### Bastion の NSG

Bastion 用の NSG は公式ドキュメントどおりに書く必要があり、省略するとデプロイが失敗する。インバウンドで GatewayManager:443 と AzureLoadBalancer:443 を許可し、アウトバウンドで VirtualNetwork:22/3389 と AzureCloud:443 を通す。

```bicep:infra/modules/hub.bicep
module nsgBastion 'br/public:avm/res/network/network-security-group:0.5.0' = {
  name: 'deploy-nsg-bastion'
  params: {
    name: 'nsg-bas-${prefix}-${location}-001'
    location: location
    tags: tags
    securityRules: [
      { name: 'Allow-GatewayManager-Inbound', priority: 100, direction: 'Inbound'
        access: 'Allow', protocol: 'Tcp', sourcePortRange: '*'
        destinationPortRange: '443', sourceAddressPrefix: 'GatewayManager'
        destinationAddressPrefix: '*' }
      { name: 'Allow-SSH-RDP-Outbound', priority: 100, direction: 'Outbound'
        access: 'Allow', protocol: '*', sourcePortRange: '*'
        destinationPortRanges: ['22', '3389'], sourceAddressPrefix: '*'
        destinationAddressPrefix: 'VirtualNetwork' }
      // ... 他のルールは省略
    ]
  }
}
```

### Private DNS Zone の集約パターン

Hub VNet に Private DNS Zone を作り、VNet リンクを張る。Spoke VNet にも Peering 後にリンクすれば、Spoke 上のリソースから PE 経由で名前解決が通る。

```bicep:infra/modules/hub.bicep
module dnsZoneBlob 'br/public:avm/res/network/private-dns-zone:0.7.0' = {
  name: 'deploy-pdz-blob'
  params: {
    name: 'privatelink.blob.${environment().suffixes.storage}'
    tags: tags
    virtualNetworkLinks: [
      { virtualNetworkResourceId: vnet.outputs.resourceId, registrationEnabled: false }
    ]
  }
}
```

`environment().suffixes.storage` を使うと、リージョンごとの FQDN 差異を吸収できる。

## Spoke モジュールの設計

Spoke は「VM を動かす場所」と「PE を張る場所」の 2 サブネット構成にした。

### VM の構成切り替え

`vmPattern` パラメータで CPU のみ / GPU のみ / 両方を切り替える。dev 環境では `vmPattern = 1`（CPU のみ）、prod では `vmPattern = 3`（両方）にしている。

```bicep:infra/modules/spoke.bicep
var deployCpuVm = vmPattern == 1 || vmPattern == 3
var deployGpuVm = vmPattern == 2 || vmPattern == 3

module cpuVm 'br/public:avm/res/compute/virtual-machine:0.12.0' = [
  for i in range(0, cpuvmNumber): if (deployCpuVm) {
    name: 'deploy-cpuvm-${i + 1}'
    params: {
      name: 'vm-cpu-${prefix}-${location}-${padLeft(string(i + 1), 3, '0')}'
      vmSize: cpuvmSku
      osType: 'Linux'
      imageReference: {
        publisher: 'RedHat'
        offer: 'RHEL'
        sku: '94_gen2'
        version: 'latest'
      }
      securityType: 'TrustedLaunch'
      secureBootEnabled: true
      vTpmEnabled: true
      customData: base64(cloudConfigCpuVm)
      // ... 省略
    }
  }
]
```

GPU VM は `secureBootEnabled: false` にしている。NVIDIA ドライバとの互換性問題で、Secure Boot を有効にするとドライバのロードに失敗するため。ここは実際にデプロイして気づいたポイントだった。

### Private Endpoint + DNS Zone Group

Storage や AI Services の PE を Spoke の `snet-pep` サブネットに配置し、`privateDnsZoneGroup` で Hub 側の DNS Zone を参照する。

```bicep:infra/modules/spoke.bicep
module storageAccount 'br/public:avm/res/storage/storage-account:0.15.0' = {
  name: 'deploy-storage'
  params: {
    name: take('st${prefix}${uniqueString(resourceGroup().id)}', 24)
    publicNetworkAccess: 'Disabled'
    networkAcls: { defaultAction: 'Deny', bypass: 'AzureServices' }
    privateEndpoints: [
      {
        subnetResourceId: vnet.outputs.subnetResourceIds[1]
        service: 'blob'
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            { privateDnsZoneResourceId: hubDnsZoneBlobId }
          ]
        }
      }
    ]
    // ...
  }
}
```

`privateDnsZoneGroup` を設定し忘れると、PE は作られるのに名前解決ができず接続失敗する。PE 周りのハマりどころとしては一番多い。

### Key Vault のセキュリティ設定

CAF 推奨に従い、アクセスポリシーではなく RBAC 認可にした。Purge Protection と Soft Delete も有効にしてある。

```bicep:infra/modules/spoke.bicep
module keyVault 'br/public:avm/res/key-vault/vault:0.11.0' = {
  name: 'deploy-keyvault'
  params: {
    name: 'kv-${prefix}-${take(uniqueString(resourceGroup().id), 6)}'
    enableRbacAuthorization: true
    enablePurgeProtection: true
    softDeleteRetentionInDays: 90
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
    lock: { kind: 'CanNotDelete', name: 'lock-kv' }
    // ...
  }
}
```

## VNet Peering のクロスリソースグループ問題

Hub と Spoke が別リソースグループにあるため、Peering を張るには双方のスコープでリソースを定義する必要がある。Bicep の `scope` を使って解決した。

```bicep:infra/modules/peering.bicep
// Hub → Spoke（Hub RG スコープ）
resource hubToSpoke 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  name: '${hubVnetName}/peer-hub-to-spoke'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    remoteVirtualNetwork: { id: spokeVnetId }
  }
}

// Spoke → Hub（別モジュールで Spoke RG にスコープ変更）
module spokeToHub 'spoke-peering.bicep' = {
  name: 'deploy-spoke-to-hub-peering'
  scope: resourceGroup(spokeRgName)
  params: {
    spokeVnetName: spokeVnetName
    hubVnetId: hubVnetId
  }
}
```

片方向だけ張って「Peering のステータスが Connected にならない」と悩んだことがある方は多いと思う。双方向ともに定義するのがポイント。

## dev / prod の切り替え

`.bicepparam` で環境差分を吸収する。

```bicepparam:infra/parameters/dev.bicepparam
using '../main.bicep'

param prefix = 'dev0001'
param vmPattern = 1          // CPU のみ
param cpuvmNumber = 1
param gpuvmNumber = 0
param enableAppGateway = false
param enableBackup = false
param enableDefender = false
param enableWorm = false
```

```bicepparam:infra/parameters/prod.bicepparam
using '../main.bicep'

param prefix = 'prd0001'
param vmPattern = 3          // CPU + GPU
param enableAppGateway = true
param enableBackup = true
param enableDefender = true
param enableWorm = true
param wormRetentionDays = 30
```

dev では GPU VM、Application Gateway、Defender、バックアップをすべて無効にしてコストを抑えている。prod でフル有効化するだけで、テンプレート自体は同じものを使い回せる。

## デプロイ手順

```bash
# 構文チェック
az bicep build --file infra/main.bicep

# 差分プレビュー（what-if）
az deployment sub what-if \
  --location japaneast \
  --template-file infra/main.bicep \
  --parameters infra/parameters/dev.bicepparam

# デプロイ実行
az deployment sub create \
  --location japaneast \
  --template-file infra/main.bicep \
  --parameters infra/parameters/dev.bicepparam
```

SSH 公開鍵と `principalId` は `.bicepparam` にプレースホルダを入れてあるので、CLI の `--parameters` で上書きするか、CI/CD パイプラインから渡す。

## ハマったところ

### Bastion サブネット名は固定

`AzureBastionSubnet` という名前でないとデプロイが失敗する。`BastionSubnet` や `snet-bastion` では通らない。Azure 側の仕様で強制されている。

### Application Gateway の AVM 対応

Application Gateway の AVM モジュール（`avm/res/network/application-gateway`）は存在するが、パラメータ構造が ARM テンプレートとかなり異なり、WAF Policy の紐付けや frontendIPConfigurations の指定で苦労した。今回は `resource` 直書きに切り替えた。AVM が成熟してきたら移行する予定。

### GPU VM と Secure Boot

`securityType: 'TrustedLaunch'` を有効にしつつ `secureBootEnabled: false` にする必要がある。NVIDIA ドライバがカーネルモジュールとして署名なしでロードされるため、Secure Boot が有効だと起動後にドライバが認識されない。

### cidrSubnet 関数の罠

Bicep の `cidrSubnet()` は便利だが、第 3 引数（index）が 0 始まりで、かつプレフィクス長によってアドレス範囲が変わる。Hub VNet で `/26`（Bastion 用）と `/24`（AppGW 用）を混在させるときは、インデックスの計算を紙に書いて確認した。

## セキュリティ上の判断

このテンプレートではゼロトラスト寄りの構成を意識した。

- 全サブネットに NSG を付与し、明示的な Deny-All ルールを末尾に置いている
- Storage と AI Services はパブリックアクセスを無効化し、PE 経由でのみ接続
- Key Vault は RBAC 認可 + ネットワーク ACL で Deny + 削除ロック
- VM は SSH 公開鍵認証のみ、パスワード認証は無効
- Bastion 経由でのみ VM にアクセス可能（パブリック IP なし）

Azure Firewall を入れるかは検討したが、PoC 用途ではコストが見合わず、Application Gateway + WAF v2 で L7 保護に絞った。

## おわりに

AVM を使うと、NSG ルールや診断設定のような「書くのは面倒だけど必要な設定」がモジュール側で吸収される。特に `diagnosticSettings` や `lock` をパラメータとして渡せるのは、リソース直書きよりも見通しが良い。

次は Azure Firewall を Hub に追加した構成と、GitHub Actions での CI/CD パイプライン構築を試したい。Spoke を複数追加したときの VNet Peering 管理も自動化できるか検証する。
