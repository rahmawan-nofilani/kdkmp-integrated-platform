# Security, Audit & Regulatory Architecture

Status: **DRAFT ARCHITECTURE BASELINE**
Regulatory content: **PENDING LEGAL VALIDATION**

## Security model

### Authentication
- Supabase Auth for identity foundation
- MFA planned for privileged roles
- secure session lifecycle
- password reset and account recovery
- first-login onboarding when applicable
- session revocation for suspended users

### Authorization
Backend/data access evaluates:
`IDENTITY + ROLE + PERMISSION + DATA SCOPE + WORKFLOW STATE + SOD + REGULATORY STATUS`

Never rely only on hidden frontend menus.

### Application protections
- input validation
- output encoding
- CSRF protections where applicable
- XSS prevention
- SQL injection prevention through parameterized access/ORM/client libraries
- file type/size validation
- rate limiting
- secure headers
- idempotency for retry-sensitive financial operations

### Secrets
Secrets never enter the repository. Environment/secret stores hold:
- service keys
- payment credentials
- integration credentials
- signing secrets

## Data classification

- PUBLIC
- INTERNAL
- CONFIDENTIAL
- RESTRICTED

Examples of RESTRICTED data:
- NIK
- financial balances
- loan records
- credentials/security data
- health records

Access to RESTRICTED data is logged and scope-controlled.

## Audit architecture

Audit is append-only from the application perspective.

Required fields include:
- who
- what
- when
- where/session/device where available
- before
- after
- why/reason
- correlation/request id
- related business entity

Critical transaction audit records must not be editable through normal UI.

Future hardening may include integrity hashing/hash-chain verification.

## Regulatory Configuration Engine

The application will not hardcode regulations as universal constants.

Suggested entities/configuration:
- regulatory_rules
- regulatory_rule_versions
- regulatory_authorizations
- legal_bases
- compliance_requirements
- compliance_controls
- compliance_evidence

Suggested status:
- DRAFT
- PENDING_VALIDATION
- ACTIVE
- SUSPENDED
- EXPIRED
- SUPERSEDED

## Hard gate pattern

For regulated modules such as Simpan Pinjam, LPG, Pupuk, Klinik, Apotek:

`MODULE_ENABLED + AUTHORIZATION_ACTIVE + USER_PERMISSION + DATA_SCOPE + WORKFLOW_VALID = TRANSACTION_ALLOWED`

If authorization is absent:

`TRANSACTION DISABLED — AUTHORIZATION REQUIRED`

## Regulatory placeholder policy

Until official documents are loaded and validated:

- legal references are marked **PENDING LEGAL VALIDATION**;
- no numerical legal limit is treated as official;
- product/approval policies remain configurable;
- mock adapters must be labeled clearly;
- no fake government API is presented as real.

## Backup & continuity

Architecture must support:
- automated backups
- point-in-time/data recovery strategy where available
- export
- restore testing
- disaster recovery procedure
- sync recovery for offline transactions
