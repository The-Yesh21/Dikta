# Dikta Landing Page & APK — Vercel Production Deployment Guide

This guide details the complete, production-grade strategy for deploying the **Dikta** static web showcase and Android APK distribution on **Vercel**.

---

## 1. Architectural Strategy: Overcoming the 100MB Limit

### The Challenge
* **Vercel File Size Ceiling:** Vercel enforces a strict **100MB per-file static asset limit** across Free (Hobby) and Pro tiers. Attempting to deploy an asset larger than 100MB directly via the Vercel CLI or Git will trigger:
  ```
  Error: The deployment contains files that are too large (limit is 100 MB per file)
  ```
* **Git & GitHub Ceiling:** GitHub rejects commits containing files larger than 100MB (`remote: error: GH001: Large files detected`).
* **Dikta Debug APK Size:** The local development build (`web/app-debug.apk`) is **245 MB** because it bundles all three CPU architectures (`arm64-v8a`, `armeabi-v7a`, `x86_64`) plus unstripped C++ symbols and the full Flutter JIT debug engine.
* **Bandwidth Economy:** On Vercel Hobby accounts, the monthly egress bandwidth limit is 100GB. Serving a 245MB file directly would exhaust the free quota after just ~400 downloads.

To solve this, we provide two bulletproof deployment architectures:

---

## 2. Deployment Architecture Options

### Method A (Recommended & Industry Standard): GitHub Releases / Cloudflare R2 / Vercel Blob Redirect

> **Best for:** The current 245MB debug APK or universal production releases. Zero bandwidth costs on Vercel, unlimited downloads, global CDN speed.

In this pattern, the static website remains hosted on Vercel's global Edge Network, while binary downloads are streamed directly from an external high-bandwidth storage provider via HTTP redirects configured in `vercel.json`.

```
                    ┌────────────────────────────┐
                    │  User Clicks "Download"    │
                    │      (/app-debug.apk)      │
                    └─────────────┬──────────────┘
                                  │
                                  ▼
               ┌─────────────────────────────────────┐
               │         Vercel Edge Network         │
               │  Redirects 307 to Release Storage   │
               └──────────────────┬──────────────────┘
                                  │
            ┌─────────────────────┴─────────────────────┐
            ▼                                           ▼
┌───────────────────────┐                   ┌───────────────────────┐
│ GitHub Releases CDN   │                   │ Cloudflare R2 / S3    │
│ (Free, 2GB/file max,  │                   │ (Zero egress fees,    │
│  unlimited bandwidth) │                   │  custom domain)       │
└───────────────────────┘                   └───────────────────────┘
```

#### Step 1: Upload APK to GitHub Releases (Takes 30 seconds)
1. Push your repository to GitHub.
2. In your GitHub repository, navigate to **Releases** > **Draft a new release**.
3. Create a tag (e.g., `v1.0.0`), write a title (`Dikta v1.0.0 Release`), and drag & drop `app-debug.apk` (or your signed release APK).
4. Click **Publish release**.
5. Copy the direct download URL of the uploaded asset:
   `https://github.com/<YOUR_GITHUB_USER>/<YOUR_REPO>/releases/download/v1.0.0/Dikta-v1.0.0.apk`

#### Step 2: Configure Redirect in `vercel.json`
Update the redirect rule in `web/vercel.json` (and root `vercel.json`):
```json
{
  "redirects": [
    {
      "source": "/app-debug.apk",
      "destination": "https://github.com/<YOUR_GITHUB_USER>/<YOUR_REPO>/releases/download/v1.0.0/Dikta-v1.0.0.apk",
      "permanent": false
    },
    {
      "source": "/download",
      "destination": "https://github.com/<YOUR_GITHUB_USER>/<YOUR_REPO>/releases/download/v1.0.0/Dikta-v1.0.0.apk",
      "permanent": false
    }
  ]
}
```
* **Result:** All "Download APK" buttons in `index.html` (which point to `app-debug.apk`) immediately stream the file from GitHub's CDN at top speeds without touching your Vercel bandwidth quota.

---

### Method B: Split Architecture Release APK (<100MB, Direct Vercel Hosting)

> **Best for:** When you want the APK hosted directly on your Vercel domain without third-party redirects.

A production release APK stripped of debug symbols and split by target CPU architecture is dramatically smaller (~30MB - 45MB), easily fitting inside Vercel's 100MB limit.

#### Step 1: Build Split Production Release APK
Run the following in the project root:
```bash
flutter build apk --release --split-per-abi
```
This generates three separate lean APKs in `build/app/outputs/flutter-apk/`:
* `app-arm64-v8a-release.apk` (~35 MB — supports 95%+ of modern Android phones)
* `app-armeabi-v7a-release.apk` (~30 MB — older 32-bit devices)
* `app-x86_64-release.apk` (~40 MB — Chromebooks & emulators)

#### Step 2: Copy the Target APK to `web/`
```bash
cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk web/app-debug.apk
```
*(Or keep the name as `Dikta-v1.0.0.apk` and update the link).*

#### Step 3: Remove from `.vercelignore`
Remove `app-debug.apk` from `web/.vercelignore` and `.vercelignore`.
Since the file is under 100MB, Vercel will upload and deploy it directly.

Our pre-configured `vercel.json` automatically supplies the necessary response headers:
```
Content-Type: application/vnd.android.package-archive
Content-Disposition: attachment; filename="Dikta-v1.0.0.apk"
Cache-Control: public, max-age=31536000, immutable
```

---

## 3. Fast 2-Minute Deployment Instructions

### Option 1: Vercel CLI (Fastest, Terminal)

1. **Install Vercel CLI (if not installed):**
   ```bash
   npm install -g vercel
   ```

2. **Login to Vercel:**
   ```bash
   vercel login
   ```

3. **Deploy from Repository Root:**
   ```bash
   # From D:\product
   vercel --prod
   ```
   * *Set up and deploy?* `Y`
   * *Which scope?* (Select your account)
   * *Link to existing project?* `N`
   * *Project name?* `dikta-app`
   * *Directory location?* `./` (Vercel automatically detects `outputDirectory: "web"` in root `vercel.json`)
   * *Override settings?* `N`

   **Or Deploy from `web/` directory directly:**
   ```bash
   cd web
   vercel --prod
   ```

---

### Option 2: GitHub Dashboard Import (Continuous Deployment)

1. Commit and push the repository to GitHub:
   ```bash
   git add .
   git commit -m "feat: configure Vercel deployment with headers and clean URLs"
   git push origin main
   ```
2. Go to [vercel.com/new](https://vercel.com/new).
3. Import your `dictation-app` GitHub repository.
4. Under **Project Settings**:
   * **Framework Preset:** `Other`
   * **Root Directory:** `./` (or `web`)
   * **Build Command:** Leave empty
   * **Output Directory:** `web` (automatically recognized from `vercel.json`)
5. Click **Deploy**. Your site will be live within 15 seconds.

---

## 4. Configuration Reference: `vercel.json`

Both `web/vercel.json` and root `vercel.json` are pre-configured with industry-standard settings:

| Setting | Purpose |
| :--- | :--- |
| `"cleanUrls": true` | Strips `.html` extensions from URLs (e.g. `/index.html` → `/`). |
| `"trailingSlash": false` | Normalizes URLs without trailing slashes for canonical SEO. |
| **MIME Type Header** | Injects `application/vnd.android.package-archive` on `*.apk` so mobile browsers immediately trigger the native Android package installer instead of rendering binary gibberish. |
| **Content-Disposition** | Enforces `attachment; filename="Dikta-v1.0.0.apk"` ensuring consistent file naming on user devices. |
| **Security Headers** | Pre-configures `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `X-XSS-Protection`, and `Referrer-Policy`. |
| **CORS Headers** | Configures `Access-Control-Allow-Origin: *` for web simulator audio and assets. |
| **Caching Rules** | 1-year immutable cache for versioned APKs (`max-age=31536000`), 1-hour stale-while-revalidate for CSS/JS, and zero-cache must-revalidate for HTML. |

---

## 5. Verification Checklist

After deploying to Vercel, verify your production URL:

- [ ] **Landing Page Render:** Visit your deployment URL (e.g., `https://dikta-app.vercel.app`). Verify custom fonts, canvas waves, and the notebook simulator are active.
- [ ] **Clean URLs:** Visit `https://dikta-app.vercel.app/` — verify that page loads without `/index.html`.
- [ ] **APK Download Response:** Run `curl -I https://dikta-app.vercel.app/app-debug.apk`:
  ```http
  HTTP/2 200 (or 307 Redirect)
  content-type: application/vnd.android.package-archive
  content-disposition: attachment; filename="Dikta-v1.0.0.apk"
  ```
- [ ] **Mobile Android Verification:** Open the URL on an Android device, tap **Download Dikta APK**, and verify that the package downloads smoothly and prompts for installation.
