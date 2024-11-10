# https://github.com/google-github-actions/auth?tab=readme-ov-file#direct-wif

if [[ "$GC_PROJECT_NAME" ]]; then
  PROJECT_NAME=$GC_PROJECT_NAME
else
  read -p "Enter Google Cloud project backend name: " PROJECT_NAME
fi
if [[ "$GC_PROJECT_DISPLAY_NAME" ]]; then
  PROJECT_DISPLAY_NAME=$GC_PROJECT_DISPLAY_NAME
else
  read -p "Enter Google Cloud project display name: " PROJECT_DISPLAY_NAME
fi
if [[ "$GC_SERVICE_USER" ]]; then
  SERVICE_USER=$GC_SERVICE_USER
else
  read -p "Enter Google Cloud service user name: " SERVICE_USER
fi

WI_POOL_NAME="github"

# login interactively using your browser
#gcloud auth login

PROJECT_ID=$(gcloud projects list --filter="name:'$PROJECT_DISPLAY_NAME'" --format="value(projectId)")

if [[ -z "$PROJECT_ID" ]]; then
  echo "No project found with the display name: $PROJECT_DISPLAY_NAME. Creating..."
  # create project
  random_suffix=$(tr -dc a-z0-9 </dev/urandom | head -c 6; echo)
  PROJECT_ID="${PROJECT_NAME}-${random_suffix}"
  echo "Creating project $PROJECT_DISPLAY_NAME (id: $PROJECT_ID)"
  gcloud projects create "$PROJECT_ID" --name="$PROJECT_DISPLAY_NAME" 
else
  echo "Project found with the display name: $PROJECT_DISPLAY_NAME (Project ID: $PROJECT_ID)"
fi

SERVICE_USER_MAIL=$(gcloud iam service-accounts list --project="${PROJECT_ID}" \
  --filter="name:'$SERVICE_USER'" \
  --format="value(email)")

if [[ -z "$SERVICE_USER_MAIL" ]]; then
  echo "No Service Account Found with the following name: $SERVICE_USER. Creating..."
  # create project
  gcloud iam service-accounts create "$SERVICE_USER" \
  --project "${PROJECT_ID}"
  SERVICE_USER_MAIL="${SERVICE_USER}@${PROJECT_ID}.iam.gserviceaccount.com"
else
  echo "Service User found with name: $SERVICE_USER (ID: $SERVICE_USER_MAIL)"
fi

WI_POOL_ID=$(gcloud iam workload-identity-pools list \
  --filter="name:'$WI_POOL_NAME'" \
  --format="value(name)" \
  --project="${PROJECT_ID}" \
  --location="global")

if [[ -z "$WI_POOL_ID" ]]; then
  echo "No Workload Identity Pool Found with the following name: $WI_POOL_NAME. Creating..."
  # create project
  gcloud iam workload-identity-pools create "$WI_POOL_NAME" \
    --project="${PROJECT_ID}" \
    --location="global" \
    --display-name="GitHub Actions Pool"
  WI_POOL_ID=$(gcloud iam workload-identity-pools describe "$WI_POOL_NAME" \
    --project="${PROJECT_ID}" \
    --location="global" \
    --format="value(name)")
else
  echo "Workload Identity Pool found with name: $WI_POOL_NAME (ID: $WI_POOL_ID)"
fi

echo "$string" | tr xyz _

OIDC_NAME="test"
echo OIDC would be $OIDC_NAME

WI_OIDC_PROVIDER=$(gcloud iam workload-identity-pools providers list \
  --project="${PROJECT_ID}" \
  --location="global" \
  --workload-identity-pool="$WI_POOL_NAME" \
  --filter="name:'$OIDC_NAME'" \
  --format="value(name)")

if [[ -z "$WI_OIDC_PROVIDER" ]]; then
  echo "No OIDC Provider Found with the following name: $WI_POOL_NAME. Creating..."
  gcloud iam workload-identity-pools providers create-oidc "$OIDC_NAME" \
    --project="${PROJECT_ID}" \
    --location="global" \
    --workload-identity-pool="$WI_POOL_NAME" \
    --display-name="GitHub OIDC provider - prod" \
    --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
    --attribute-condition="assertion.repository_owner == '${github_org}'" \
    --issuer-uri="https://token.actions.githubusercontent.com"
    WI_OIDC_PROVIDER=$(gcloud iam workload-identity-pools providers describe "$OIDC_NAME" \
      --project="${PROJECT_ID}" \
      --location="global" \
      --workload-identity-pool="$WI_POOL_NAME" \
      --format="value(name)")
else
  echo "OIDC Provider found with name: $OIDC_NAME (ID: $WI_OIDC_PROVIDER)"
fi

# Allow authentications from the Workload Identity Pool to your Google Cloud Service Account.
gcloud iam service-accounts add-iam-policy-binding "${SERVICE_USER_MAIL}" \
  --project="${PROJECT_ID}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/${WI_POOL_ID}/attribute.repository/${GITHUB_REPOSITORY}"

# grant service user owner rights to read/write resources in project
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --role="roles/owner" \
  --member="serviceAccount:${SERVICE_USER_MAIL}"

# finally, enabled resource manager api for your project (required by terraform!)
gcloud services enable 'cloudresourcemanager.googleapis.com' --project "$PROJECT_ID"
gcloud services enable 'iamcredentials.googleapis.com' --project "$PROJECT_ID"
gcloud services enable 'androidpublisher.googleapis.com' --project "$PROJECT_ID"

# gh cli login required for additional access rights!
# https://github.com/cli/cli/issues/3799
GITHUB_TOKEN_CACHE=$GITHUB_TOKEN
export GITHUB_TOKEN=""
gh auth login

gh secret set GCP_WORKLOAD_PROVIDER --body "$WI_OIDC_PROVIDER"
gh secret set GCP_PROJECT_ID --body "$PROJECT_ID"
gh secret set GCP_SERVICE_ACCOUNT_ID --body "$SERVICE_USER_MAIL"

# optionally, a storage bucket can be created as well:
bucket_name="${PROJECT_NAME}_terraform"
bucket_prefix="terraform/state"
gcloud storage buckets create gs://${bucket_name} --location="US-EAST1" --project="$PROJECT_ID"
# then, set secrets for github
gh secret set GCP_BACKEND_BUCKET --body "$bucket_name"
gh secret set GCP_BACKEND_PREFIX --body "$bucket_prefix"

# restore auth token!
export GITHUB_TOKEN=$GITHUB_TOKEN_CACHE

echo Script has finished successfully 🎉