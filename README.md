# GCPわからん

## Overview

わからんのでWorkload Identity連携のセットアップを自動化することにした

## Usage

### 1. GCPプロジェクトを作成または既存のプロジェクトを選択し、プロジェクトIDを控えておく

新しく作成する場合:

```
$ gcloud projects create <project_id> --name <project name>
```

(既存プロジェクトのIDを取得する場合は `gcloud projects list` の出力からIDを探す)

### 2. 生成したプロジェクトのIDを渡してセットアップスクリプトを実行

1. `setup.sh` を実行 (詳細なオプションはスクリプトファイルを参照のこと)  

    ```
    $./setup.sh <service_account_name> <pool_name> <provider_name>
    ```

1. gcloud CLIを検索する (以降の操作はここで発見できた`gcloud`を用いて行われる)

    ```
    gcloud CLI: /path/to/gcloud
    ```

1. コマンドライン引数を整理する

    ```
    Command-line arguments:
        project ID: <project_id>
        service account name: <service_account_name>
        workload identity pool id: <pool_name>
        workload identity provider id: <provider_name>
    ```

1. プロジェクトの状態を確認する

    ```
    Project status: ACTIVE
    ```

1. サービスアカウントを検索する

    存在しない場合はここで作成できる

    ```
    Check service account [<service_account_name>] ... not found
    No service account named <service_account_name>. Create it now? (y/N) > y
    service account was created successfully.
    ```

    存在する場合はメールアドレスが表示される

    ```
    Check service account [<service_account_name>] ... <service_account_name>@<project_id>.iam.gserviceaccount.com
    ```

1. 必要なAPIが有効になっているか確認する

    有効になっていない場合は自動で有効化される

    ```
    Check iam credentials api status ... enabled
    ```

1. Workload Identityプールを検索する

    存在しない場合はここで作成できる

    ```
    Check workload identity pool [<pool_name>] ... not found
    No workload identity pool named <pool_name>. Create it now? (y/N) > y
    workload identity pool was created successfully.
    ```

    存在する場合はプール名が表示される

    ```
    Check workload identity pool [<pool_name>] ... projects/<project_id>/locations/global/workloadIdentityPools/<pool_name>
    ```

1. Workload Identityプロバイダを検索する

    存在しない場合はここで作成できる

    ```
    Check workload identity provider [<provider_name>] ... not found
    No workload identity provider named <provider_name>. Create it now? (y/N) > y
    workload identity provider was created successfully.
    ```

    存在する場合はプロバイダ名が表示される

    ```
    Check workload identity provider [<pool_name>] ... projects/<project_id>/locations/global/workloadIdentityPools/<pool_name>/providers/<provider_name>
    ```

ここまでの手順でGCPプロジェクトの構成が完了する。続いて対象リポジトリの登録に移る。

1. 対象のリポジトリ名を入力

    `オーナー/リポジトリ名` の形式で入力する

    ```
    Type target repository (e.g. google/chrome) > <repo_name>
    ```

1. IAMポリシーバインディングを追加する

    前の手順で入力したリポジトリからの認証のみ受け付けるよう構成される
    
    ```
    Add IAM policy binding for repository <repo_name> ...
    ```

最後にGitHub Actionsのworkflowに設定するべき値が表示され、スクリプトは終了する。

```
---------------------------------------
|         Operaiton finished          |
---------------------------------------

Now, you can authenticate to Google Cloud from GitHub Actions using google-github-actions/auth with parameters shown below:

- id: 'auth'
  name: 'Authenticate to Google Cloud'
  uses: 'google-github-actions/auth@v1'
  with:
    workload_identity_provider: "<provider_name>"
    service_account: "<service_account>"
```

### 3. ワークフローを構成

出力された情報を元にワークフローを構成する。この際、サービスアカウントのメールアドレスとWorkload Identityプロバイダ名はリポジトリシークレットとして保持する。

例:

```yml
name: google-auth

on:
  push:

jobs:
  google_api_access:
    runs-on: ubuntu-latest

    permissions:
      id-token: write
      contents: read

    steps:
      - uses: "actions/checkout@v3"

      - id: auth
        name: 'Authenticate to Google Cloud'
        uses: google-github-actions/auth@v1
        with:
          workload_identity_provider: ${{ secrets.GOOGLE_WORKLOAD_IDENTITY_PROVIDER_NAME }}
          service_account: ${{ secrets.GOOGLE_SERVICE_ACCOUNT_EMAIL }}
```

## NOTE

本スクリプトの実行に際し発生した問題について、Enchan1207は一切の責任を負いません。
認証情報やサービスアカウントは[Googleのベストプラクティス](https://cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys?hl=ja)等に従って管理してください。

## License

This repository is published under [MIT License](LICENSE).

## Reference

 - [google-github-actions/auth](https://github.com/marketplace/actions/authenticate-to-google-cloud#setting-up-workload-identity-federation)
 - [Workload Identity federation](https://cloud.google.com/iam/docs/workload-identity-federation?hl=ja)
