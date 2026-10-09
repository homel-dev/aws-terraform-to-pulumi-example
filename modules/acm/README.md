# ACM module

YAML files under the invoking stack's `config/` directory define certificates.

Modes:

- `managed_dns`: create an ACM certificate and DNS validation records in the Route53 zone owned by the sibling `route53` stack.
- `imported`: consume an ACM certificate ARN imported or provisioned outside this stack.

In `imported` mode, Terraform references the supplied ARN through an output;
it does **not** import or own the certificate's ACM lifecycle or private key.
In `managed_dns` mode, the module creates a new ACM certificate and manages
its Route 53 DNS-validation records. Existing seed-owned certificates remain
outside this module's resource ownership when used in `imported` mode.
