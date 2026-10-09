#!/usr/bin/env python3
"""Overlay roadmap resources on the deployed POC graph without Terraform apply.

The existing stacks come from their read-only S3 states. The RDS, WAF and
GuardDuty nodes are explicitly marked planned and inferred from YAML, not from
a Terraform plan or AWS resources.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml


DEPLOYED_STACKS = (
    "terraform-state",
    "vpc",
    "iam",
    "logging",
    "route53",
    "acm",
    "firewall",
    "ec2",
    "dlm",
)


def load_graph_builder():
    path = Path(__file__).with_name("build-architecture-graph.py")
    spec = importlib.util.spec_from_file_location("myorg_architecture_graph", path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    sys.dont_write_bytecode = True
    spec.loader.exec_module(module)
    return module


def fetch_states(bucket: str, profile: str, region: str) -> dict:
    states = {}
    with tempfile.TemporaryDirectory(prefix="myorg-roadmap-state-") as directory:
        for stack in DEPLOYED_STACKS:
            destination = Path(directory) / f"{stack}.tfstate"
            subprocess.run(
                [
                    "/home/salieksanov/.local/bin/aws", "--profile", profile, 
                    "--region", region, "s3", "cp",
                    f"s3://{bucket}/myorg/poc/use1/{stack}/terraform.tfstate",
                    str(destination), "--only-show-errors",
                ],
                check=True,
            )
            states[stack] = json.loads(destination.read_text())
    return states


def deployed_resources(states: dict, graph_builder) -> list:
    resources = []
    for stack in DEPLOYED_STACKS:
        for item in states[stack].get("resources", []):
            if item.get("mode") != "managed" or not item.get("type", "").startswith("aws_"):
                continue
            for instance in item.get("instances", []):
                index = instance.get("index_key")
                name = "_".join(
                    part
                    for part in (stack, item.get("name", "resource"), str(index) if index is not None else "")
                    if part
                )
                resources.append(graph_builder.Resource(stack, item["type"], name, instance.get("attributes") or {}))
    return resources


def overlay_roadmap(resources: list, states: dict, graph_builder, location: Path) -> None:
    vpc_config = yaml.safe_load((location / "vpc/config/vpc.yml").read_text())
    rds = yaml.safe_load((location / "rds/config/database.yml").read_text())
    waf = yaml.safe_load((location / "waf/config/waf.yml").read_text())
    yaml.safe_load((location / "guardduty/config/guardduty.yml").read_text())

    vpc = states["vpc"]["outputs"]["vpcs"]["value"][rds["vpc_key"]]
    compute = states["ec2"]["outputs"]["computes"]["value"][rds["compute_key"]]
    waf_compute = states["ec2"]["outputs"]["computes"]["value"][waf["compute_key"]]
    prefix = "-".join(location.parts[-3:])

    def add(kind: str, name: str, attributes: dict) -> None:
        resources.append(graph_builder.Resource("planned", kind, name, attributes))

    def subnet_id(subnet_key: str) -> str:
        if subnet_key in vpc["subnet_ids"]:
            return vpc["subnet_ids"][subnet_key]
        config = vpc_config["subnets"][subnet_key]
        identifier = f"planned-subnet-{subnet_key}"
        add(
            "aws_subnet", f"planned_{subnet_key}",
            {
                "id": identifier,
                "vpc_id": vpc["vpc_id"],
                "availability_zone": config["availability_zone"],
                "cidr_block": config["cidr"],
            },
        )
        return identifier

    subnet_group = f"{prefix}-rds"
    security_group = "planned-rds-security-group"
    add("aws_db_subnet_group", "planned_rds_subnets", {
        "name": subnet_group,
        "subnet_ids": [subnet_id(rds["subnet"]), subnet_id(rds["standby_subnet"])],
    })
    add("aws_db_instance", "planned_rds_mysql_multi_az", {
        "db_subnet_group_name": subnet_group,
        "engine": "mysql",
        "multi_az": True,
        "vpc_security_group_ids": [security_group],
    })
    for source, name in (
        (compute["application_security_group_id"], "application"),
        (compute["database_security_group_id"], "migration_source"),
    ):
        add("aws_vpc_security_group_ingress_rule", f"planned_rds_from_{name}", {
            "referenced_security_group_id": source,
            "security_group_id": security_group,
        })

    web_acl_arn = "planned-waf-web-acl-arn"
    add("aws_wafv2_web_acl", "planned_waf_alb", {"arn": web_acl_arn})
    add("aws_wafv2_web_acl_association", "planned_waf_alb_association", {
        "web_acl_arn": web_acl_arn,
        "resource_arn": waf_compute["alb_arn"],
    })
    add("aws_guardduty_detector", "planned_guardduty_regional", {})


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bucket", required=True)
    parser.add_argument("--profile", default="default")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    location = Path(__file__).resolve().parents[1] / "deployments/myorg/poc/use1"
    region = yaml.safe_load((location / "location.yml").read_text())["region"]
    graph_builder = load_graph_builder()
    states = fetch_states(args.bucket, args.profile, region)
    resources = deployed_resources(states, graph_builder)
    overlay_roadmap(resources, states, graph_builder, location)
    graph = graph_builder.build_graph(resources)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(graph, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
