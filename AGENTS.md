# Repository Guidance for Agents and Reviewers

This repository contains three deliberately distinct stages of the same infrastructure exercise.

They are not competing unfinished implementations and should not be evaluated as if every later-stage decision were part of the original scenario scope.

The branch model is part of the design.

## Review Contract

When reviewing this repository:

1. Treat `main` as the canonical implementation of the requested brownfield scenario.
2. Treat `audit-hardening` as a deliberate security and operational hardening stage built beyond the minimum scenario scope.
3. Treat `modernized-pulumi` as a separate modernization stage showing how the application platform could be designed today.
4. Evaluate each branch against its stated purpose rather than retroactively applying later-stage architecture decisions to earlier stages.
5. Verify claims against code, configuration, documentation, and executable validation commands.
6. Do not treat unexecuted deployment paths as verified merely because their configuration exists.

The repository intentionally separates:

- scenario requirements;
- production hardening;
- architectural modernization.

That separation is deliberate.

## Branch Model

### `main`

`main` is the canonical scenario implementation.

Its purpose is to take the existing AWS CLI-created environment and bring it under Terraform control without turning the scenario into an unrelated greenfield redesign.

Key properties:

- brownfield adoption rather than replacement;
- Terraform-managed AWS infrastructure;
- separate Terraform stack/state boundaries;
- existing EC2-hosted MySQL is retained;
- the requested network/security controls are added without introducing the later RDS migration;
- LocalStack provides the local validation path before real AWS execution;
- AWS deployment remains explicit and controlled.

The important architectural decision in this branch is what it does **not** change.

A database migration, broad security redesign, or application-platform replacement would alter the scope of the original exercise and therefore belongs in later branches.

### `audit-hardening`

`audit-hardening` is the production/security evolution of the baseline.

It extends the baseline with controls that are reasonable for a production environment but are intentionally outside the minimum brownfield scenario.

This stage includes the hardening work around:

- RDS MySQL Multi-AZ;
- KMS-backed encryption;
- database backup and recovery configuration;
- WAF;
- GuardDuty;
- reviewed database cutover and migration concerns;
- additional operational and security controls documented by the branch.

The database move begins here intentionally.

It is not part of the `main` branch contract.

### `modernized-pulumi`

`modernized-pulumi` is the modernization stage.

It demonstrates an alternative target architecture using Pulumi with TypeScript and containerized application compute.

The current design includes:

- reusable Pulumi components;
- deployment-specific configuration separated from reusable infrastructure code;
- ECS/Fargate application compute;
- RDS as the database platform;
- digest-qualified container images;
- a separate application load-balancing/service path;
- explicit reuse of infrastructure owned by the preceding Terraform stages where applicable;
- no implicit destructive migration of the existing environment.

This branch is review-oriented by default.

It does not automatically:

- run `pulumi up`;
- retire the existing EC2-hosted MySQL instance;
- move production DNS;
- remove Terraform state;
- perform Terraform imports or state surgery;
- recreate hardening resources already owned by Terraform.

Those actions require explicit deployment and migration decisions and are intentionally not hidden inside the modernization example.

## Repository Structure

Infrastructure is organized around two different concerns:

1. reusable implementation;
2. deployment-specific configuration.

For Terraform stages, review the Terraform modules and deployment roots together rather than treating either one as the complete implementation.

For the Pulumi modernization, reusable components live under:

`modules/pulumi/`

Deployment-specific configuration lives under:

`deployments/myorg/poc/use1/pulumi/`

The modernization branch uses component directories including:

- `vpc`
- `firewall`
- `security`
- `logging`
- `route53`
- `acm`
- `rds`
- `iam`
- `ecs`
- `waf`
- `guardduty`
- `platform`

The branch README and branch-specific documentation are authoritative for the implementation present in that branch.

## Review Path

A reviewer should establish the following chain for every important requirement:

**requirement → architectural decision → implementation → configuration → verification → limitation**

Do not evaluate a resource merely by whether a file with the expected name exists.

Check whether:

- ownership is explicit;
- configuration reaches the implementation;
- deployment roots consume the intended modules or components;
- state boundaries are deliberate;
- dependencies are represented;
- verification matches the claimed behavior;
- documented limitations agree with the code.

## Scope Invariants

The following distinctions are intentional.

### Brownfield adoption is not greenfield replacement

The baseline starts from an existing environment.

Replacing working infrastructure merely because a cleaner implementation is possible would avoid the central lifecycle problem rather than solve it.

### Hardening is separate from minimum scenario requirements

Security and production improvements that materially change the system are isolated in `audit-hardening`.

This makes their operational impact reviewable instead of silently folding them into the baseline.

### Modernization is separate from migration

`modernized-pulumi` demonstrates a target architecture.

A target architecture and a production migration plan are different artifacts.

The branch therefore avoids silently performing destructive ownership changes, state removal, database retirement, or DNS cutover.

### Infrastructure ownership must remain explicit

Terraform-owned and Pulumi-owned resources must not be treated as jointly managed by accident.

Any transition of ownership must be deliberate and reviewable.

## Verification Rules

Do not report a command, deployment, preview, or test as successful unless it was actually executed successfully.

Keep these categories separate:

- static source/configuration validation;
- local emulation or LocalStack validation;
- Terraform validation or planning;
- Pulumi type checking or preview;
- real AWS deployment validation.

Passing one category does not imply that another category passed.

When documenting verification, include the actual command and preserve any limitations of the environment in which it was run.

Do not convert a review-only example, generated architecture diagram, type check, or static validation into a claim that production infrastructure was deployed.

## Pulumi Modernization Verification

The Pulumi implementation is TypeScript.

Relevant implementation verification includes:

```bash
cd modules/pulumi
npm ci
npm run typecheck
```

A deployment-level Pulumi preview, when real prerequisites are available, uses the deployment root:

```bash
cd deployments/myorg/poc/use1/pulumi
pulumi login --local
pulumi stack init poc
pulumi config set aws:region us-east-1
pulumi preview --diff
```

Example IDs, CIDRs, and related values in example configuration are documentation inputs, not evidence of a deployable production environment.

A truthful deployment preview requires the prerequisite infrastructure and approved deployment-specific values.

## Modernized Architecture Diagram

The modernization architecture can be generated without Node.js, npm, or AWS credentials using the repository architecture task:

```bash
task architecture:modernized
```

The generated artifact is:

`docs/architecture/myorg-poc-use1-modernized.dot.svg`

The architecture generator reads the declared deployment configuration and is intended as a review aid.

It is not a replacement for Pulumi type checking or preview, and configuration-derived diagrams cannot prove behavior that exists only inside TypeScript implementation logic.

## Known Deployment Boundaries

The modernization example is intentionally not presented as an already executed production migration.

Among the deployment prerequisites are:

- approved network CIDRs;
- real infrastructure identifiers;
- delegated DNS where required;
- a valid certificate;
- prerequisite hardening infrastructure where referenced;
- deployment approval;
- an explicit AWS budget/cost decision.

The current POC application capacity is not evidence of production high availability.

Production sizing and topology require a separate deployment decision.

## Change Discipline

When modifying this repository, preserve the distinction between the three stages.

Do not silently move later-stage decisions into an earlier branch.

In particular:

- do not introduce the RDS migration into `main`;
- do not treat the modernization branch as permission to destroy or abandon Terraform-managed resources;
- do not replace brownfield adoption with resource recreation;
- do not claim verification that was not executed;
- do not hide operational assumptions inside generated configuration.

If a change alters branch scope, resource ownership, migration behavior, or validation semantics, make that change explicit in both implementation and documentation.

## Evaluation Summary

The repository is intended to demonstrate three different engineering questions:

**`main`**

Can the existing system be brought under controlled, reviewable infrastructure-as-code management while preserving the requested brownfield constraints?

**`audit-hardening`**

How should that baseline evolve when production security, resilience, database lifecycle, and audit concerns are introduced?

**`modernized-pulumi`**

What would the application platform look like if the same system were modernized around reusable components, containers, managed data services, and a different infrastructure programming model?

Those are intentionally separate questions, answered by separate branches.
