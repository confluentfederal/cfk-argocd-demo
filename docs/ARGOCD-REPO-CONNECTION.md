# Connecting ArgoCD to the Confluent Federal Repository

## Steps

1. **Access ArgoCD UI**
   - Navigate to your ArgoCD URL
   - Login with `admin` / your ArgoCD password

2. **Add Repository**
   - Click **Settings** (gear icon) → **Repositories** → **+ Connect Repo**

3. **Configure Connection**
   - Choose **VIA HTTPS**
   - **Repository URL:** `https://github.com/confluentfederal/cfk-argocd-demo.git`
   - **Username:** Your GitHub username
   - **Password:** GitHub Personal Access Token

4. **Create GitHub PAT** (if needed)
   - GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
   - Generate new token with `repo` scope
   - Copy and use as password

5. **Click Connect**
   - Verify green checkmark / "Successful" status
