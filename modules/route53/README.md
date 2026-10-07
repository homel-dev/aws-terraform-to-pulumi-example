# Route53 module

This module intentionally follows the configuration pattern used by the Homel development Terraform modules:

- stack-owned YAML under `${path.root}/config`;
- one directory per hosted zone;
- `zone.yml` plus optional `records/*.yml`;
- schema validation through `tlkamp/validation`;
- reusable module logic with no backend configuration.

Example:

```text
config/
└── example.com/
    ├── zone.yml
    └── records/
        └── www.yml
```
