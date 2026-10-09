#!/usr/bin/env python3
"""Combine deployed MyOrg POC Terraform states into a TerraVision graph.

Only Terraform-managed AWS resource identities and explicit state references are
used. Raw state attributes are never copied into the generated graph.
"""

from __future__ import annotations

import argparse
import json
import re
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any


STACKS = (
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

# A logical infrastructure view, not a graph of Terraform bookkeeping objects.
VISIBLE_TYPES = {
    "aws_vpc",
    "aws_subnet",
    "aws_route_table",
    "aws_internet_gateway",
    "aws_nat_gateway",
    "aws_lb",
    "aws_launch_template",
    "aws_autoscaling_group",
    "aws_instance",
    "aws_networkfirewall_firewall",
    "aws_vpc_endpoint",
    "aws_route53_zone",
    "aws_acm_certificate",
    "aws_s3_bucket",
    "aws_cloudtrail",
    "aws_flow_log",
    "aws_dlm_lifecycle_policy",
    "aws_secretsmanager_secret",
}


@dataclass
class Resource:
    stack: str
    kind: str
    name: str
    attrs: dict[str, Any]
    nodes: tuple[str, ...] = ()


def slug(value: object) -> str:
    result = re.sub(r"[^a-z0-9]+", "_", str(value).lower()).strip("_")
    return result or "unnamed"


def strings(value: Any) -> list[str]:
    if isinstance(value, str):
        return [value] if value else []
    if isinstance(value, (list, tuple, set)):
        return [item for item in value if isinstance(item, str) and item]
    return []


def objects(value: Any) -> list[dict[str, Any]]:
    if isinstance(value, dict):
        return [value]
    if isinstance(value, list):
        return [item for item in value if isinstance(item, dict)]
    return []


def load_resources(state_dir: Path) -> list[Resource]:
    result: list[Resource] = []
    for stack in STACKS:
        state = json.loads((state_dir / f"{stack}.tfstate").read_text())
        for resource in state.get("resources", []):
            if resource.get("mode") != "managed" or not resource.get("type", "").startswith("aws_"):
                continue
            for instance in resource.get("instances", []):
                index = instance.get("index_key")
                name = "_".join(
                    part
                    for part in (stack, resource.get("name", "resource"), str(index) if index is not None else "")
                    if part
                )
                result.append(Resource(stack, resource["type"], name, instance.get("attributes") or {}))
    return result


def icon_type(resource: Resource) -> str:
    if resource.kind == "aws_lb":
        return "aws_nlb" if resource.attrs.get("load_balancer_type") == "network" else "aws_alb"
    return resource.kind


def subnet_ids(resource: Resource) -> list[str]:
    attrs = resource.attrs
    if resource.kind == "aws_lb":
        return strings(attrs.get("subnets")) or [
            item["subnet_id"] for item in objects(attrs.get("subnet_mapping")) if item.get("subnet_id")
        ]
    if resource.kind == "aws_autoscaling_group":
        return strings(attrs.get("vpc_zone_identifier"))
    if resource.kind == "aws_vpc_endpoint":
        return strings(attrs.get("subnet_ids"))
    if resource.kind == "aws_networkfirewall_firewall":
        return [item["subnet_id"] for item in objects(attrs.get("subnet_mapping")) if item.get("subnet_id")]
    return strings(attrs.get("subnet_id"))


def resource_security_groups(resource: Resource) -> list[str]:
    attrs = resource.attrs
    if resource.kind == "aws_launch_template":
        return [
            group
            for interface in objects(attrs.get("network_interfaces"))
            for group in strings(interface.get("security_groups"))
        ]
    if resource.kind == "aws_lb":
        return strings(attrs.get("security_groups"))
    if resource.kind == "aws_instance":
        return strings(attrs.get("vpc_security_group_ids"))
    if resource.kind == "aws_vpc_endpoint":
        return strings(attrs.get("security_group_ids"))
    return []


def build_graph(resources: list[Resource]) -> dict[str, list[str]]:
    graph: dict[str, set[str]] = defaultdict(set)
    used_names: set[str] = set()
    by_id: dict[str, Resource] = {}
    by_arn: dict[str, Resource] = {}

    for resource in resources:
        for index_key, directory in (("id", by_id), ("arn", by_arn)):
            value = resource.attrs.get(index_key)
            if isinstance(value, str) and value:
                directory[value] = resource

    def make_node(kind: str, name: str) -> str:
        base = f"{kind}.{slug(name)}"
        candidate = base
        sequence = 2
        while candidate in used_names:
            candidate = f"{base}_{sequence}"
            sequence += 1
        used_names.add(candidate)
        graph[candidate]
        return candidate

    for resource in resources:
        if resource.kind not in VISIBLE_TYPES:
            continue
        ids = list(dict.fromkeys(subnet_ids(resource)))
        # Multi-subnet resources are drawn once in each subnet, not in two boxes at once.
        count = len(ids) if len(ids) > 1 else 1
        resource.nodes = tuple(
            make_node(icon_type(resource), f"{resource.name}_{index + 1}" if count > 1 else resource.name)
            for index in range(count)
        )

    vpcs = {r.attrs.get("id"): r for r in resources if r.kind == "aws_vpc" and r.nodes}
    subnets = {r.attrs.get("id"): r for r in resources if r.kind == "aws_subnet" and r.nodes}

    for vpc in vpcs.values():
        graph["tv_aws_region.us_east_1"].add(vpc.nodes[0])

    zones: dict[tuple[str, str], str] = {}
    for subnet in subnets.values():
        vpc_id = subnet.attrs.get("vpc_id")
        vpc = vpcs.get(vpc_id)
        if vpc is None:
            continue
        az = subnet.attrs.get("availability_zone")
        if isinstance(az, str) and az:
            zone_key = (str(vpc_id), az)
            if zone_key not in zones:
                zones[zone_key] = make_node("tv_aws_az", f"{vpc.name}_{az}")
                graph[vpc.nodes[0]].add(zones[zone_key])
            graph[zones[zone_key]].add(subnet.nodes[0])
        else:
            graph[vpc.nodes[0]].add(subnet.nodes[0])

    # Autoscaling groups own launch templates, which provide the visual workload
    # node even though ASG-created EC2 instances are not Terraform-managed.
    for group in resources:
        if group.kind != "aws_autoscaling_group" or not group.nodes:
            continue
        for item in objects(group.attrs.get("launch_template")):
            template = by_id.get(item.get("id"))
            if template and template.kind == "aws_launch_template" and template.nodes:
                for group_node in group.nodes:
                    graph[group_node].add(template.nodes[0])

    for resource in resources:
        if not resource.nodes or resource.kind in {"aws_vpc", "aws_subnet", "aws_launch_template"}:
            continue
        identifiers = list(dict.fromkeys(subnet_ids(resource)))
        for index, node in enumerate(resource.nodes):
            subnet_id = identifiers[index] if len(identifiers) > 1 else (identifiers[0] if identifiers else None)
            subnet = subnets.get(subnet_id)
            if subnet:
                graph[subnet.nodes[0]].add(node)
                continue
            vpc = vpcs.get(resource.attrs.get("vpc_id") or resource.attrs.get("resource_id"))
            if vpc:
                graph[vpc.nodes[0]].add(node)

    # References in security-group ingress rules describe allowed communication,
    # not observed traffic; no speculative links are introduced.
    sg_consumers: dict[str, set[str]] = defaultdict(set)
    for resource in resources:
        for security_group in resource_security_groups(resource):
            sg_consumers[security_group].update(resource.nodes)
    for rule in resources:
        if rule.kind != "aws_vpc_security_group_ingress_rule":
            continue
        source = rule.attrs.get("referenced_security_group_id")
        destination = rule.attrs.get("security_group_id")
        for start in sg_consumers.get(source, ()):
            for end in sg_consumers.get(destination, ()):
                if start != end:
                    graph[start].add(end)

    # ALB listeners and ASG target-group membership provide direct routing links.
    groups_by_target: dict[str, list[Resource]] = defaultdict(list)
    for group in resources:
        if group.kind == "aws_autoscaling_group" and group.nodes:
            for target in strings(group.attrs.get("target_group_arns")):
                groups_by_target[target].append(group)
    for listener in resources:
        if listener.kind != "aws_lb_listener":
            continue
        load_balancer = by_arn.get(listener.attrs.get("load_balancer_arn"))
        if not load_balancer or not load_balancer.nodes:
            continue
        for action in objects(listener.attrs.get("default_action")):
            target_arns = strings(action.get("target_group_arn"))
            for forward in objects(action.get("forward")):
                target_arns.extend(
                    target["arn"]
                    for target in objects(forward.get("target_group"))
                    if isinstance(target.get("arn"), str)
                )
            for target_arn in target_arns:
                for group in groups_by_target.get(target_arn, ()):
                    targets = [
                        node
                        for node in graph[group.nodes[0]]
                        if node.startswith("aws_launch_template.")
                    ]
                    for load_balancer_node in load_balancer.nodes:
                        graph[load_balancer_node].update(targets)

    return {node: sorted(targets) for node, targets in sorted(graph.items())}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--states-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    graph = build_graph(load_resources(args.states_dir))
    args.output.write_text(json.dumps(graph, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
