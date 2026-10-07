# Boot Artifact Security Boundary

## 1. Current contract

The scenario states that the application cannot start until a required artifact/package is retrieved from an external host during instance boot.

`main` preserves that behavior deliberately.

## 2. Why the POC does not mirror it

The artifact may be ordinary cacheable software, but it may also be customer-controlled intellectual property, a tenant-specific extension, or another object that is intentionally permitted to exist only inside an authorized runtime boundary.

Until that contract is known, the implementation MUST NOT silently create a persistent copy in S3, a package mirror, or a golden AMI.

## 3. Baseline control

The baseline uses:

- a generic trusted application AMI;
- HTTPS-only retrieval;
- a narrow TLS-SNI allowlist in Network Firewall;
- optional SHA-256 verification when an expected digest is provided;
- no generic application Internet egress;
- firewall and CloudTrail evidence around the infrastructure change.

## 4. Follow-up decision

After ownership/cacheability is confirmed, the artifact lifecycle MAY evolve to one of:

- remain ephemeral and customer-hosted;
- copy into an authorized internal mirror;
- bake into an immutable AMI;
- move into a signed container/image supply chain.

The decision belongs in a later reviewed architecture change, not in the baseline POC.
