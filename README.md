# Enterprise Identity Lab — Entra ID Architecture, Federation & Identity Threat Detection

A hands-on identity & access management (IAM) lab built from a blank Microsoft Entra ID tenant. The project provisions an enterprise-style identity environment, layers on Conditional Access, builds a real OAuth 2.0 / OIDC application, and finishes with identity governance and threat detection wired into a Wazuh SIEM. Everything is built and documented as code where possible (PowerShell + Microsoft Graph).

> Built as a portfolio project to demonstrate practical IAM skills — identity architecture, access management, workload identity, governance, and identity threat detection — aligned to the Microsoft **SC-300** (Identity and Access Administrator) domain.

---

## Why this lab exists

Most "I know IAM" claims stop at definitions. This lab is the opposite: a real tenant, real policies, real tokens, real detections — including the messy parts (eventual consistency, role-vs-billing separation, security-defaults-to-Conditional-Access migration) that you only learn by building. Each phase ships working artifacts *and* a write-up of the decisions and lessons behind them.

---

## Architecture at a glance

| Layer | What it covers |
|-------|----------------|
| **Identity foundation** | Cloud-native admin, break-glass account, 15 test users, static + dynamic groups |
| **Access management** | Conditional Access baseline (MFA, legacy-auth block, admin MFA, location control) |
| **Workload identity** | Registered app, OIDC auth-code flow + PKCE, app roles / RBAC, token analysis |
| **Governance & detection** | PIM (JIT admin), access reviews, sign-in/audit logs → Wazuh, identity detections |

---

## Phases

### Phase 1 — Tenant foundation & access management ✅
Provision the tenant and establish least-privilege access controls.
- Cloud-native Global Admin separated from the tenant-owner identity
- Dedicated **break-glass** account, excluded from all Conditional Access
- 15 test users across IT / Finance / HR with department attributes
- Static groups (`sg-it`, `sg-hr`) + a **dynamic** group (`sg-finance-dynamic`) driven by `user.department`
- Security defaults disabled in favour of custom Conditional Access
- Conditional Access baseline (staged report-only → enforced):
  - **CA001** Require MFA for all users
  - **CA002** Block legacy authentication
  - **CA003** Require MFA for admin / privileged roles
  - **CA004** Block sign-ins from outside Australia
- 📄 Write-up: [`docs/phase1-access-management.md`](docs/phase1-access-management.md)
- 🔧 Scripts: [`scripts/Deploy-Phase1-Lab.ps1`](scripts/Deploy-Phase1-Lab.ps1), [`scripts/Deploy-CA-Policies.ps1`](scripts/Deploy-CA-Policies.ps1)

### Phase 2 — Workload identity & OAuth/OIDC app ✅
- Registered a single-tenant application in Entra ID (SPA platform, PKCE, no implicit grant)
- Built a single-page app using the **OIDC authorization-code flow with PKCE** (MSAL.js)
- **Token deep-dive** — ID token vs access token (audience, issuer), key claims, and the `amr` claim showing Phase 1's MFA policy in the token
- **App roles + RBAC** — defined and assigned roles, producing a `roles` claim consumed by the app
- Write-up: Firebase Authentication vs Entra ID — an architectural comparison
- 📄 Write-up: [`docs/phase2-oidc-pkce.md`](docs/phase2-oidc-pkce.md)
- 🔧 App: [`app/index.html`](app/index.html)

### Phase 3 — Identity governance & threat detection 🔜
- **Privileged Identity Management** — eligible (just-in-time) admin assignments
- Access reviews
- Forward Entra **sign-in & audit logs** to a self-hosted **Wazuh** SIEM
- Identity detections: impossible travel, failed-MFA spikes, off-hours PIM activation, privileged-group additions
- Attack simulation + incident write-up

---

## Tech stack

- **Microsoft Entra ID P2** (managed trial)
- **PowerShell 7** + **Microsoft Graph PowerShell SDK**
- **MSAL** (Phase 2)
- **Wazuh** SIEM (Phase 3)

---

## Repository structure

```
entra-id-identity-lab/
├── README.md
├── docs/                       # Phase write-ups, decisions, lessons learned
│   ├── phase1-access-management.md
│   ├── phase2-oidc-pkce.md
│   └── images/                 # Evidence screenshots
├── scripts/                    # PowerShell / Graph deployment scripts
│   ├── Deploy-Phase1-Lab.ps1
│   └── Deploy-CA-Policies.ps1
├── app/                        # Phase 2 — OIDC + PKCE single-page app
│   └── index.html
└── detections/                 # Phase 3 — Wazuh rules & detection logic
```

---

## A note on secrets

No live credentials are committed to this repository. The break-glass password and any tenant secrets are stored offline in a password manager. Deployment scripts generate passwords at runtime rather than hard-coding them. The lab tenant is a disposable trial tenant.

---

*Author: Aakash Ramamoorthy — Master of Cyber Security, RMIT University*
