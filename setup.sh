#!/bin/bash
#
# GitHubのリポジトリ用にWorkload Identity連携をセットアップする
# 2023 Enchan1207 (https://github.com/Enchan1207/gcp-wakaran)
#

#
# Usage: ./setup.sh プロジェクトの名前またはID [サービスアカウント名] [Workload Identity プール名] [Workload Identity プロバイダ名]
#   鉤括弧で括った引数はオプションです。指定のない場合以下の値が使用されます:
#     - サービスアカウント名: gha-agent
#     - Workload Identity プール名: gha-pool
#     - Workload Identity プロバイダ名: gha-provider
#
#   このシェルスクリプトは、既存のGCPプロジェクトにWorkload Identity連携を構成し、
#   特定のリポジトリからGoogle Cloudリソースにアクセスするための設定を行います。
#   実行には gloud CLI (https://cloud.google.com/sdk/gcloud) が必要です。
#
#   参考: https://github.com/marketplace/actions/authenticate-to-google-cloud#setting-up-workload-identity-federation
#

# ユーザに入力させる
# 第一引数: プロンプト
# 第一引数: 入力がない場合にどちらに倒すか (デフォルト: n)
choose(){
    # プロンプトを構成
    prompt=${1:-"continue?"}
    default_choise=`echo ${2:=n} | tr '[:lower:]' '[:upper:]'`
    if [ $default_choise = "Y" ];then
        prompt="$prompt (Y/n)"
    else
        prompt="$prompt (y/N)"
    fi

    # 有効な入力が得られるまで繰り返す
    choose_status=1
    while [ $choose_status -ne 0 ]; do
        echo -n "$prompt > "
        read choise
        choise=`echo ${choise:=$default_choise} | tr '[:lower:]' '[:upper:]'`

        # 入力がなければデフォルト値を採用
        if [ -z $choise ]; then
            choise=$default_choise
            choose_status=0
            continue
        fi

        # yかnならそのまま通す
        if [ $choise = "Y" -o $choise = "N" ]; then
            choose_status=0
            continue
        fi
    done

    # 入力がyなら0 そうでなければ1を返す
    [ $choise = "Y" ]
    return $?
}

# gcloud CLIのパスを取得
GCLOUD=`which gcloud`
if [ $? -ne 0 ]; then
    echo "Google Cloud CLI not found"
    exit 1
fi
echo "gcloud CLI: $GCLOUD"

# 実行引数の確認
if [ $# -eq 0 ]; then
    echo "$0 project_id [service_account_name] [workload identity pool name] [workload identity provider name]"
    exit 1
fi
PROJECT_ID=$1
SERVICE_ACCOUNT_NAME=$2
WORKLOAD_IDENTITY_POOL_IDENTIFIER=$3
WORKLOAD_IDENTITY_PROVIDER_IDENTIFIER=$4
echo "Command-line arguments:"
echo "    project ID: $PROJECT_ID"
echo "    service account name: ${SERVICE_ACCOUNT_NAME:=my-gha-agent}"
echo "    workload identity pool id: ${WORKLOAD_IDENTITY_POOL_IDENTIFIER:=my-gha-pool}"
echo "    workload identity provider id: ${WORKLOAD_IDENTITY_PROVIDER_IDENTIFIER:=my-gha-provider}"

# プロジェクトが存在し、アクセス可能かつアクティブであることを確認
echo -n "Project status: "
PROJECT_STATUS=`$GCLOUD projects describe $PROJECT_ID --format="value(lifecycleState)" 2>/dev/null`
if [ $? -ne 0 ]; then
    echo "UNKNOWN"
    echo "Failed to get project status"
    exit 1
fi
echo $PROJECT_STATUS
if [ $PROJECT_STATUS != "ACTIVE" ]; then
    echo "Unable to determine whether project is valid and active"
    exit 1
fi

# プロジェクトナンバーを取得しておく(Workload Identityプールの検索に必要)
PROJECT_NUMBER=`$GCLOUD projects describe $PROJECT_ID --format="value(projectNumber)"`

# 該当サービスアカウントが存在するか確認 必要に応じて作る
echo -n "Check service account [$SERVICE_ACCOUNT_NAME] ... "
SERVICE_ACCOUNT_EMAIL=`$GCLOUD iam service-accounts list --project $PROJECT_ID --format="value(EMAIL)" | grep "^$SERVICE_ACCOUNT_NAME@"`
if [ $? -ne 0 ]; then
    echo "not found"

    choose "No service account named $SERVICE_ACCOUNT_NAME. Create it now?" "n"
    if [ $? -ne 0 ]; then
        echo "Abort"
        exit 1
    fi

    $GCLOUD iam service-accounts create $SERVICE_ACCOUNT_NAME --project "$PROJECT_ID"
    if [ $? -ne 0 ]; then
        echo "Failed to create service account"
        exit 1
    fi

    echo "service account was created successfully."
    SERVICE_ACCOUNT_EMAIL=`$GCLOUD iam service-accounts list --project $PROJECT_ID --format="value(EMAIL)" | grep "^$SERVICE_ACCOUNT_NAME@"`
else
    echo $SERVICE_ACCOUNT_EMAIL
fi


# IAM Credentials APIを有効化
echo -n "Check iam credentials api status ... "
if [ -z `$GCLOUD services list --project $PROJECT_ID --format="value(NAME)" | grep "^iamcredentials.googleapis.com$"` ]; then
    $GCLOUD services enable iamcredentials.googleapis.com --project "$PROJECT_ID"
else
    echo -n "already "
fi
echo "enabled"

# Workload Identity プールの確認 必要に応じて作る
echo -n "Check workload identity pool [$WORKLOAD_IDENTITY_POOL_IDENTIFIER] ... "
WORKLOAD_IDENTITY_POOL_NAME=`gcloud iam workload-identity-pools describe $WORKLOAD_IDENTITY_POOL_IDENTIFIER --location global --project $PROJECT_ID --format="value(name)" 2>/dev/null`
if [ $? -ne 0 ]; then
    echo "not found"

    choose "No workload identity pool named $WORKLOAD_IDENTITY_POOL_IDENTIFIER. Create it now?" "n"
    if [ $? -ne 0 ]; then
        echo "Abort"
        exit 1
    fi

    $GCLOUD iam workload-identity-pools create "$WORKLOAD_IDENTITY_POOL_IDENTIFIER" \
        --project="$PROJECT_ID" \
        --location="global" \
        --display-name="GitHub Actions"

    if [ $? -ne 0 ]; then
        echo "Failed to create workload identity pool"
        exit 1
    fi

    echo "workload identity pool was created successfully."
    WORKLOAD_IDENTITY_POOL_NAME=`gcloud iam workload-identity-pools describe $WORKLOAD_IDENTITY_POOL_IDENTIFIER --location global --project $PROJECT_ID --format="value(name)" 2>/dev/null`
else
    echo $WORKLOAD_IDENTITY_POOL_NAME
fi

# Workload Identity プロバイダの確認 必要に応じて作る
echo -n "Check workload identity provider [$WORKLOAD_IDENTITY_PROVIDER_IDENTIFIER] ... "
WORKLOAD_IDENTITY_PROVIDER_NAME=`gcloud iam workload-identity-pools providers describe $WORKLOAD_IDENTITY_PROVIDER_IDENTIFIER --workload-identity-pool $WORKLOAD_IDENTITY_POOL_IDENTIFIER --location global --project $PROJECT_ID --format="value(name)"`
if [ $? -ne 0 ]; then
    echo "not found"

    choose "No workload identity provider named $WORKLOAD_IDENTITY_PROVIDER_IDENTIFIER. Create it now?" "n"
    if [ $? -ne 0 ]; then
        echo "Abort"
        exit 1
    fi

    $GCLOUD iam workload-identity-pools providers create-oidc "$WORKLOAD_IDENTITY_PROVIDER_IDENTIFIER" \
        --project="$PROJECT_ID" \
        --location="global" \
        --workload-identity-pool="$WORKLOAD_IDENTITY_POOL_IDENTIFIER" \
        --display-name="GitHub Actions OIDC" \
        --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository" \
        --issuer-uri="https://token.actions.githubusercontent.com"

    if [ $? -ne 0 ]; then
        echo "Failed to create workload identity provider"
        exit 1
    fi

    echo "workload identity provider was created successfully."
    WORKLOAD_IDENTITY_PROVIDER_NAME=`gcloud iam workload-identity-pools providers describe $WORKLOAD_IDENTITY_PROVIDER_IDENTIFIER --workload-identity-pool $WORKLOAD_IDENTITY_POOL_IDENTIFIER --location global --project $PROJECT_ID --format="value(name)"`
else
    echo $WORKLOAD_IDENTITY_PROVIDER_NAME
fi

# 環境確認完了
echo "Confirmed project configuration"

# 対象のリポジトリ名を入力
IS_VALID_REPO_NAME=1
while [ $IS_VALID_REPO_NAME -ne 0 ]; do
    echo -n "Type target repository (e.g. google/chrome) > "
    read REPO_NAME

    # バリデーション
    [[ $REPO_NAME =~ "^([A-Za-z0-9\._-]+)\/([A-Za-z0-9\._-]+)$" ]]; IS_VALID_REPO_NAME=$?
done

# IAMポリシーバインディングを追加
echo "Add IAM policy binding for repository $REPO_NAME ..."
$GCLOUD iam service-accounts add-iam-policy-binding "${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --project="${PROJECT_ID}" \
    --role="roles/iam.workloadIdentityUser" \
    --member="principalSet://iam.googleapis.com/${WORKLOAD_IDENTITY_POOL_NAME}/attribute.repository/${REPO_NAME}"
if [ $? -ne 0 ]; then
    echo "Failed to add IAM policy binding"
    exit 1
fi

# 完了
cat <<EOS


---------------------------------------
|         Operaiton finished          |
---------------------------------------

Now, you can authenticate to Google Cloud from GitHub Actions using google-github-actions/auth with parameters shown below:

- id: 'auth'
  name: 'Authenticate to Google Cloud'
  uses: 'google-github-actions/auth@v1'
  with:
    workload_identity_provider: "$WORKLOAD_IDENTITY_PROVIDER_NAME"
    service_account: "$SERVICE_ACCOUNT_EMAIL"

EOS
