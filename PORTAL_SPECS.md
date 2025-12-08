# v0 Spec – Self-Service API Key Portal

**APISIX + OIDC (mock IdP now, Entra ID later)**

## 1. Goal

Build an internal portal where an authenticated user can:

1. Log in via **OIDC** (fronted by APISIX).
2. Be mapped 1:1 to an **APISIX Consumer** (by OIDC subject/Entra OID).
3. Manage **exactly one `key-auth` API key** via the **APISIX Credential API**:

   * **Get key** – create Consumer + key if missing, otherwise return existing key.
   * **Recycle key** – rotate the key by updating the single `key-auth` credential.

**Constraints / Intent**

* APISIX remains the **source of truth** for Consumers and credentials.
* The portal is a thin UI + client of the APISIX **Admin API**.
* The portal never talks directly to the IdP (mock or Entra).

---

## 2. OIDC / IdP Strategy

### 2.1 Abstraction

From the portal’s point of view there is only:

* “APISIX is protecting `/portal` and injecting identity headers.”

The portal does **not** care whether the IdP is:

* Local Keycloak / IdentityServer (dev), or
* Microsoft Entra ID (prod).

It only reads headers from APISIX.

### 2.2 v0: Local / Mock OIDC Provider

For v0 we run a local IdP, for example:

* **Keycloak in Docker** (or IdentityServer, etc.), with:

  * One “test realm” / “test tenant”.
  * A few test users (alice, bob, etc).

APISIX `openid-connect` plugin is configured to:

* Use the mock IdP’s discovery URL, client_id, client_secret.
* Protect the **Portal route** (e.g. `/portal`).
* After successful auth, **inject headers** to the portal upstream:

  * `X-User-Oid` – set to the IdP’s `sub` (or a configured stable claim).
  * `X-User-Name` – display name (for UI only).
  * `X-User-Email` – email/UPN (for UI only).

We treat `X-User-Oid` as the stand-in for “Entra OID”.

### 2.3 Later: Swap to Entra ID

When Entra ID tenant + client details are available:

* Only APISIX configuration changes:

  * `openid-connect.discovery` → Entra discovery URL
    `https://login.microsoftonline.com/<TENANT_ID>/v2.0/.well-known/openid-configuration`
  * `client_id`, `client_secret`, scopes, redirect URI.

* APISIX still:

  * Injects `X-User-Oid` (now the real **Entra OID**).
  * Optionally injects `X-User-Name`, `X-User-Email`.

**Portal code stays unchanged** as long as the header names remain the same.

---

## 3. Data Model

### 3.1 Consumer (1:1 with user)

Each OIDC user (mock or Entra) maps to **exactly one APISIX Consumer**.

* For v0, mapping rule:

  * `username = <X-User-Oid>`
  * `custom_id = <X-User-Oid>`

(We may refine later to use userPrincipalName or similar, but v0 pins to OID/subject.)

Example Consumer created by the portal:

```json
{
  "username": "<x_user_oid>",
  "custom_id": "<x_user_oid>",
  "desc": "Created and managed by SSO portal",
  "labels": {
    "source": "oidc-portal-v0"
  }
}
```

### 3.2 Credential (`key-auth` via Credential API)

We use the APISIX **Credential API** (not inline plugin config) and enforce:

* For any portal-managed Consumer:

  * There is **0 or 1** `key-auth` credential.
  * Never more than one in v0.

This future-proofs us for v1 multi-key support while keeping v0 simple.

---

## 4. Key Generation & Handling

### 4.1 Generation

The portal backend generates keys using a **CSPRNG** and base64url encoding.

* 32 bytes of randomness → base64url string.
* Example approach (conceptual):

  * Generate 32 random bytes using a CSPRNG.
  * Encode to base64url.

  (e.g. in Python: `secrets.token_urlsafe(32)`)

### 4.2 Ownership, Storage & Logging

* **APISIX** (Credential API) stores the canonical key value.
* The **portal**:

  * Displays the full key **only** when user hits “Get key” or “Recycle key”.
  * **Must not log** the full key.
  * May log:

    * `user_oid`, consumer id, credential id,
    * timestamps and action type (created / reused / rotated),
    * optional hashed/truncated fingerprint of the key.

---

## 5. Portal Behavior

### 5.1 Identity Resolution

Every request to the portal arrives via APISIX:

1. Read `X-User-Oid` from the request headers.
2. If missing/invalid → 401/403.
3. Optionally read:

   * `X-User-Name` and `X-User-Email` for display only.

No direct OIDC or cookie validation in the portal; APISIX owns that.

### 5.2 Consumer Resolution

Given `user_oid = X-User-Oid`:

1. Use Admin API to **find Consumer** where:

   * `username == user_oid` (or `custom_id == user_oid`).

2. If Consumer exists → use it.

3. If Consumer does not exist → create it:

   ```json
   {
     "username": "<user_oid>",
     "custom_id": "<user_oid>",
     "desc": "Created by SSO portal",
     "labels": {
       "source": "oidc-portal-v0"
     }
   }
   ```

No `key-auth` plugin attached at Consumer level; keys are managed via Credential API.

### 5.3 “Get key”

**User story:** “As an authenticated user, I want to see my API key.”

Backend flow:

1. Resolve identity (`user_oid`).
2. Resolve or auto-create Consumer for `user_oid`.
3. Via Credential API, list `key-auth` credentials for that Consumer.

   * If **exactly one** credential exists:

     * Return its `key` to frontend.
   * If **none** exist:

     * Generate new key (CSPRNG base64url).
     * Create a `key-auth` credential with that key for this Consumer.
     * Return the new key.

UI:

* Show:

  * The key value (full).
  * Note that key is sensitive and must be stored safely.

### 5.4 “Recycle key”

**User story:** “As an authenticated user, I want to rotate my API key.”

Backend flow:

1. Resolve identity and Consumer.
2. List `key-auth` credentials for the Consumer.

   * If **none** exist:

     * Treat as “Get key”: generate a new key and create the credential.
   * If **one** exists:

     * Generate a new key.
     * Update that credential to the new key (or delete+recreate; but keep exactly one).
     * Return the new key.

UI:

* Show:

  * The new key.
  * Message that **any previous key is now invalid**.

**Invariant:** Before and after rotation there is at most **one** `key-auth` credential.

### 5.5 Minimal v0 UI

* “Signed in as: `<X-User-Name>` (`<X-User-Email>`).”
* Section “Your API key”:

  * If key exists:

    * Show the key.
    * Button: **“Recycle key”**.
  * If no key exists:

    * Show “You don’t have a key yet.”
    * Button: **“Get key”**.

No multi-key UI, labels, or advanced metadata in v0.

---

## 6. APISIX Responsibilities

### 6.1 OIDC Plugin + Mock IdP

* Configure `openid-connect` plugin against local Keycloak/IdentityServer:

  * Discovery URL, client_id, client_secret.
  * Appropriate scopes (e.g. `openid profile`).
  * Redirect URI pointing to APISIX route.
* Attach plugin to the **portal route**.
* After login, inject headers:

  * `X-User-Oid` from `sub` (or another stable ID claim).
  * Optional `X-User-Name`, `X-User-Email`.

### 6.2 Later: Switch to Entra ID

* Reconfigure plugin to:

  * Use Entra discovery URL.
  * Use Entra client_id/client_secret.
  * Map Entra OID claim to `X-User-Oid`.

* Keep header names intact so the portal doesn’t need code changes.

### 6.3 Credential / Key-auth

* Use `key-auth` plugin on backend API routes.
* Configure it to look up keys created via the Credential API.
* Ensure the portal backend can reach APISIX Admin API with a secure admin token/mTLS, ideally constrained to Consumer + Credential operations.

---

## 7. Security & Audit

* Only the **portal backend** holds the Admin API credentials; never expose them to the browser.
* Never log full key values.
* Log key lifecycle events (create / reuse / rotate) with `user_oid`, consumer id, credential id, timestamp, and optional hashed/truncated key fingerprint.

---

If you want, I can also write a tiny “dev checklist” (e.g. 1) start Keycloak container, 2) create realm/client/user, 3) configure APISIX OIDC, 4) verify `/portal` redirects & injects headers) that you can add as a separate subticket.
