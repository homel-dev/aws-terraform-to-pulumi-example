# ACM module

YAML files under the invoking stack's `config/` directory define certificates.

Modes:

- `managed_dns`: create an ACM certificate and DNS validation records in the Route53 zone owned by the sibling `route53` stack.
- `imported`: consume an ACM certificate ARN imported or provisioned outside this stack.

Brownfield certificates should be imported into the managed resource address rather than rediscovered procedurally by expiry status.
