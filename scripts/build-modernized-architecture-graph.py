#!/usr/bin/env python3
"""Build the planned Pulumi architecture from YAML, offline and without Node.

This is a schematic derived from Pulumi deployment config and the known
component topology, not a Pulumi preview or a representation of AWS state.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

import yaml


TYPE_MAP = {
    "aws:ec2/vpc:Vpc": "aws_vpc",
    "aws:ec2/subnet:Subnet": "aws_subnet",
    "aws:ec2/routeTable:RouteTable": "aws_route_table",
    "aws:ec2/internetGateway:InternetGateway": "aws_internet_gateway",
    "aws:ec2/natGateway:NatGateway": "aws_nat_gateway",
    "aws:ec2/vpcEndpoint:VpcEndpoint": "aws_vpc_endpoint",
    "aws:ec2/flowLog:FlowLog": "aws_flow_log",
    "aws:ec2/securityGroup:SecurityGroup": "aws_security_group",
    "aws:vpc/securityGroupIngressRule:SecurityGroupIngressRule": "aws_vpc_security_group_ingress_rule",
    "aws:lb/loadBalancer:LoadBalancer": "aws_lb",
    "aws:lb/listener:Listener": "aws_lb_listener",
    "aws:lb/targetGroup:TargetGroup": "aws_lb_target_group",
    "aws:ecs/cluster:Cluster": "aws_ecs_cluster",
    "aws:ecs/service:Service": "aws_ecs_service",
    "aws:ecs/taskDefinition:TaskDefinition": "aws_ecs_task_definition",
    "aws:ecr/repository:Repository": "aws_ecr_repository",
    "aws:rds/subnetGroup:SubnetGroup": "aws_db_subnet_group",
    "aws:rds/instance:Instance": "aws_db_instance",
    "aws:networkfirewall/firewall:Firewall": "aws_networkfirewall_firewall",
    "aws:networkfirewall/ruleGroup:RuleGroup": "aws_networkfirewall_rule_group",
    "aws:networkfirewall/firewallPolicy:FirewallPolicy": "aws_networkfirewall_firewall_policy",
    "aws:cloudwatch/logGroup:LogGroup": "aws_cloudwatch_log_group",
    "aws:cloudtrail/trail:Trail": "aws_cloudtrail",
    "aws:s3/bucket:Bucket": "aws_s3_bucket",
    "aws:iam/role:Role": "aws_iam_role",
    "aws:secretsmanager/secret:Secret": "aws_secretsmanager_secret",
    "aws:acm/certificate:Certificate": "aws_acm_certificate",
    "aws:route53/zone:Zone": "aws_route53_zone",
    "aws:route53/record:Record": "aws_route53_record",
    "aws:wafv2/webAcl:WebAcl": "aws_wafv2_web_acl",
    "aws:wafv2/webAclAssociation:WebAclAssociation": "aws_wafv2_web_acl_association",
    "aws:guardduty/detector:Detector": "aws_guardduty_detector",
}

# Architecture view: omit bookkeeping, route tables and per-service policies
# while preserving the actual registered network and workload resources.
ARCHITECTURE_VISIBLE = {
    "aws_vpc", "aws_subnet", "aws_internet_gateway", "aws_nat_gateway",
    "aws_lb", "aws_ecs_cluster", "aws_ecs_service", "aws_ecr_repository",
    "aws_db_instance", "aws_networkfirewall_firewall", "aws_vpc_endpoint",
    "aws_route53_zone", "aws_route53_record", "aws_acm_certificate",
    "aws_s3_bucket", "aws_cloudtrail", "aws_secretsmanager_secret",
    "aws_wafv2_web_acl", "aws_guardduty_detector",
}

SHARED = {
    "aws_ecr_repository", "aws_cloudwatch_log_group", "aws_s3_bucket",
    "aws_cloudtrail", "aws_iam_role", "aws_secretsmanager_secret",
    "aws_acm_certificate", "aws_ecs_cluster",
}

SECURITY = {
    "aws_guardduty_detector", "aws_wafv2_web_acl",
    "aws_networkfirewall_rule_group", "aws_networkfirewall_firewall_policy",
}

SPECIAL_NAMES = {
    "aws_ecs_service": "aws_ecs_fargate",
    "aws_db_instance": "aws_rds_mysql",
}


def snake(s: str) -> str:
    return re.sub(r"(?<!^)(?=[A-Z])", "_", s).lower()


def tf_keys(obj):
    if isinstance(obj, list):
        return [tf_keys(x) for x in obj]
    if isinstance(obj, dict):
        return {snake(key): tf_keys(value) for key, value in obj.items()}
    return obj


def load_builder(root: Path):
    file = root / "scripts/build-architecture-graph.py"
    spec = importlib.util.spec_from_file_location("myorg_architecture_graph", file)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    module.VISIBLE_TYPES = ARCHITECTURE_VISIBLE
    return module


def select(resources, kind: str, name: str | None = None):
    return [r for r in resources if r.kind == kind and (name is None or r.name == name)]


def add_edge(graph: dict[str, set[str]], source, target) -> None:
    for start in source.nodes:
        for end in target.nodes:
            if start != end:
                graph[start].add(end)


def planned_resources(root: Path) -> list[dict]:
    """Describe the logical resources instantiated by the Pulumi components.

    IDs are placeholders used only to connect nodes in the offline graph.
    Resource and subnet choices come from deployments/.../pulumi/config/*.yml.
    """
    directory = root / "deployments/myorg/poc/use1/pulumi/config"
    config = {
        path.stem: yaml.safe_load(path.read_text())
        for path in directory.glob("*.yml")
    }
    for required in ("location", "vpc", "firewall", "database", "application", "dns", "security", "logging"):
        if required not in config:
            raise ValueError(f"Missing Pulumi config: {directory / (required + '.yml')}")

    region = config["location"]["region"]
    vpc = config["vpc"]
    app = config["application"]
    firewall = config["firewall"]
    database = config["database"]
    dns = config["dns"]
    security = config["security"]
    logging = config["logging"]
    resources: list[dict] = []

    def add(resource_type: str, logical_name: str, **inputs) -> str:
        identifier = f"planned-{resource_type.replace(':', '-').replace('/', '-')}-{logical_name}"
        resources.append({"type": resource_type, "name": logical_name, "id": identifier, "inputs": inputs})
        return identifier

    def arn(identifier: str) -> str:
        return f"arn:aws:offline:::resource/{identifier}"

    vpc_id = add("aws:ec2/vpc:Vpc", "vpc", cidrBlock=vpc["cidr"])
    subnet_ids = {
        name: add(
            "aws:ec2/subnet:Subnet", f"subnet-{name}",
            vpcId=vpc_id, cidrBlock=subnet["cidr"],
            availabilityZone=subnet["availability_zone"],
        )
        for name, subnet in vpc["subnets"].items()
    }

    def subnets(names: list[str]) -> list[str]:
        return [subnet_ids[name] for name in names]

    add("aws:ec2/internetGateway:InternetGateway", "internet-gateway", vpcId=vpc_id)
    add(
        "aws:networkfirewall/firewall:Firewall", "egress", vpcId=vpc_id,
        subnetMappings=[{"subnetId": subnet_ids[firewall["firewall_subnet"]]}],
    )
    add("aws:ec2/natGateway:NatGateway", "nat", subnetId=subnet_ids[firewall["nat_public_subnet"]])

    security_groups = {
        name: add("aws:ec2/securityGroup:SecurityGroup", name, vpcId=vpc_id)
        for name in ("alb", "app", "rds", "endpoints")
    }
    for name, source, target in (
        ("alb-to-app", "alb", "app"),
        ("app-to-db", "app", "rds"),
        ("app-to-aws-endpoints", "app", "endpoints"),
    ):
        add(
            "aws:vpc/securityGroupIngressRule:SecurityGroupIngressRule", f"{name}-ingress",
            referencedSecurityGroupId=security_groups[source],
            securityGroupId=security_groups[target],
        )

    app_subnets = subnets(app["subnet_names"])
    for service in ("ecr.api", "ecr.dkr", "logs", "secretsmanager"):
        add(
            "aws:ec2/vpcEndpoint:VpcEndpoint", f"endpoint-{service.replace('.', '-')}",
            vpcId=vpc_id, subnetIds=app_subnets,
            securityGroupIds=[security_groups["endpoints"]],
            serviceName=f"com.amazonaws.{region}.{service}",
        )
    add(
        "aws:ec2/vpcEndpoint:VpcEndpoint", "endpoint-s3",
        vpcId=vpc_id, serviceName=f"com.amazonaws.{region}.s3",
    )

    add("aws:ecr/repository:Repository", "application")
    add("aws:ecs/cluster:Cluster", "application")
    alb_id = add(
        "aws:lb/loadBalancer:LoadBalancer", "application", vpcId=vpc_id,
        loadBalancerType="application", subnets=subnets(app["public_subnet_names"]),
        securityGroups=[security_groups["alb"]],
    )
    add(
        "aws:ecs/service:Service", "application",
        networkConfiguration={"subnets": app_subnets, "securityGroups": [security_groups["app"]]},
        desiredCount=app["desired_count"],
    )

    group_name = f"{vpc['name']}-db-subnets"
    add(
        "aws:rds/subnetGroup:SubnetGroup", "database",
        name=group_name, subnetIds=subnets(database["subnet_names"]),
    )
    add(
        "aws:rds/instance:Instance", "mysql", engine="mysql", multiAz=True,
        dbSubnetGroupName=group_name,
        vpcSecurityGroupIds=[security_groups["rds"]],
    )
    add("aws:secretsmanager/secret:Secret", "application-database-credential")

    add("aws:s3/bucket:Bucket", "audit", forceDestroy=logging["force_destroy"])
    add("aws:cloudtrail/trail:Trail", "regional-trail")
    add("aws:route53/zone:Zone", "public", name=dns["zone_name"])
    add("aws:route53/record:Record", "application-alias", name=dns["application_domain"])
    if dns["certificate_mode"] == "managed_dns":
        add("aws:acm/certificate:Certificate", "application", domainName=dns["application_domain"])
        add("aws:route53/record:Record", "application-cert-validation")

    acl_id = add("aws:wafv2/webAcl:WebAcl", "application", rules=security["waf_rules"])
    add(
        "aws:wafv2/webAclAssociation:WebAclAssociation", "application",
        resourceArn=arn(alb_id), webAclArn=arn(acl_id),
    )
    if security["enable_guardduty"]:
        add("aws:guardduty/detector:Detector", "regional", enable=True)
    return resources


def transform(root: Path, raw: list) -> dict[str, list[str]]:
    builder = load_builder(root)
    converted = []
    for entry in raw:
        kind = TYPE_MAP.get(entry["type"])
        if not kind:
            continue
        attrs = tf_keys(entry["inputs"])
        attrs["id"] = entry["id"]
        attrs["arn"] = f'arn:aws:offline:::resource/{entry["id"]}'
        if kind == "aws_ecs_service":
            network = attrs.get("network_configuration", {})
            attrs["subnet_ids"] = network.get("subnets", [])
            attrs["vpc_security_group_ids"] = network.get("security_groups", [])
        if kind == "aws_db_subnet_group":
            attrs["name"] = entry["inputs"].get("name", entry["name"])
        if kind == "aws_networkfirewall_firewall":
            attrs["subnet_mapping"] = attrs.get("subnet_mappings", [])
        resource = builder.Resource("modernized", kind, entry["name"], attrs)
        converted.append(resource)

    generated = builder.build_graph(converted)
    graph = defaultdict(set, {k: set(v) for k, v in generated.items()})
    region = "tv_aws_region.us_east_1"
    graph[region]
    graph["aws_group.shared_services"]
    graph["aws_group.regional_security"]
    graph[region].update(("aws_group.shared_services", "aws_group.regional_security"))

    for resource in converted:
        if not resource.nodes:
            continue
        if resource.kind in SHARED:
            graph["aws_group.shared_services"].update(resource.nodes)
        if resource.kind in SECURITY:
            graph["aws_group.regional_security"].update(resource.nodes)
            graph[region].difference_update(resource.nodes)
        if resource.kind in {"aws_route53_zone", "aws_route53_record"}:
            graph[region].update(resource.nodes)
        # For app services the Pulumi inputs identify the exact network subnets.
        if resource.kind == "aws_ecs_service":
            for subnet in select(converted, "aws_subnet"):
                if subnet.attrs["id"] in resource.attrs.get("subnet_ids", []):
                    graph[subnet.nodes[0]].update(resource.nodes)

    # Route tables belong to their associated subnets in this view.
    subnets_by_id = {r.attrs["id"]: r for r in select(converted, "aws_subnet")}
    route_tables_by_id = {r.attrs["id"]: r for r in select(converted, "aws_route_table")}
    for item in raw:
        if item["type"] != "aws:ec2/routeTableAssociation:RouteTableAssociation":
            continue
        subnet = subnets_by_id.get(item["inputs"].get("subnetId"))
        route_table = route_tables_by_id.get(item["inputs"].get("routeTableId"))
        if subnet and route_table:
            graph[subnet.nodes[0]].update(route_table.nodes)
            for node in route_table.nodes:
                graph["aws_vpc.vpc"].discard(node)

    def first(kind, name=None):
        result = select(converted, kind, name)
        return result[0] if result else None

    alb = first("aws_lb", "application")
    app = first("aws_ecs_service", "application")
    db = first("aws_db_instance", "mysql")
    fw = first("aws_networkfirewall_firewall", "egress")
    nat = first("aws_nat_gateway", "nat")
    ecr = first("aws_ecr_repository", "application")
    secret = first("aws_secretsmanager_secret", "application-database-credential")
    acl = first("aws_wafv2_web_acl", "application")
    dns = first("aws_route53_record", "application-alias")
    zone = first("aws_route53_zone", "public")
    log_bucket = first("aws_s3_bucket", "audit")
    trail = first("aws_cloudtrail", "regional-trail")

    for start, end in [
        (alb, app), (app, db), (app, ecr), (app, secret),
        (app, fw), (fw, nat), (trail, log_bucket), (dns, acl),
        (zone, dns),
    ]:
        if start and end:
            add_edge(graph, start, end)

    if acl and alb:
        add_edge(graph, acl, alb)
    if dns:
        graph["tv_aws_users.clients"].update(dns.nodes)
    if nat:
        graph["tv_aws_internet.egress"]
        for node in nat.nodes:
            graph[node].add("tv_aws_internet.egress")

    # The JSON source has no plan attributes; choose the documented icon
    # specialization and ~N copies for per-AZ ALB/RDS visualization.
    translations = {}
    for resource in converted:
        for index, node in enumerate(resource.nodes, 1):
            kind = SPECIAL_NAMES.get(resource.kind)
            if kind:
                pretty = builder.slug(resource.name)
                new_node = f"{kind}.{pretty}~{index}" if len(resource.nodes) > 1 else f"{kind}.{pretty}"
                translations[node] = new_node
            elif resource.kind == "aws_lb":
                pretty = builder.slug(resource.name)
                translations[node] = (
                    f"aws_alb.{pretty}~{index}" if len(resource.nodes) > 1
                    else f"aws_alb.{pretty}"
                )
    renamed = defaultdict(set)
    for source, targets in graph.items():
        src = translations.get(source, source)
        renamed[src].update(translations.get(target, target) for target in targets)
    return {k: sorted(v) for k, v in sorted(renamed.items())}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    raw = planned_resources(root)
    graph = transform(root, raw)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(graph, indent=2, sort_keys=True) + "\n")
    print(f"Planned Pulumi resources: {len(raw)}, TerraVision nodes: {len(graph)}", file=sys.stderr)


if __name__ == "__main__":
    main()
