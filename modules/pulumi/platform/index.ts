import * as pulumi from "@pulumi/pulumi";
import {VpcComponent} from "../vpc";
import {FirewallComponent} from "../firewall";
import {SecurityComponent} from "../security";
import {LoggingComponent} from "../logging";
import {Route53Component} from "../route53";
import {AcmComponent} from "../acm";
import {RdsComponent} from "../rds";
import {IamComponent} from "../iam";
import {EcsComponent} from "../ecs";
import {WafComponent} from "../waf";
import {GuardDutyComponent} from "../guardduty";
import {loadEnvironment} from "./config";

// This entrypoint lives in the reusable implementation tree. The Pulumi
// deployment directory contains only Pulumi.yaml and environment YAML.
const config = loadEnvironment();
const awsRegion = new pulumi.Config("aws").require("region");
if (awsRegion !== config.region || config.region !== "us-east-1") {
    throw new Error("MyOrg POC is restricted to us-east-1");
}

const prefix = "myorg-poc-use1-modern";
const tags = {
    Project: "myorg-aws-poc",
    Purpose: "pci-dss-network-control",
    BusinessUnit: "myorg",
    Environment: "poc",
    Location: "use1",
    Region: config.region,
    ManagedBy: "Pulumi",
};
const common = {namePrefix: prefix, tags};

const network = new VpcComponent("network", {
    ...common,
    cidr: config.vpc.cidr,
    subnets: config.vpc.subnets,
});
const security = new SecurityComponent("security", {
    ...common,
    vpcId: network.vpcId,
    applicationPort: config.application.app_port,
    databasePort: config.database.port,
    approvedIngressCidrs: config.security.approved_ingress_cidrs,
});
const firewall = new FirewallComponent("firewall", {
    ...common,
    vpcId: network.vpcId,
    internetGateway: network.internetGateway,
    subnetIds: network.subnetIds,
    subnetCidrs: network.subnetCidrs,
    routeTableIds: network.routeTableIds,
    applicationSubnet: config.firewall.application_subnet,
    firewallSubnet: config.firewall.firewall_subnet,
    natPublicSubnet: config.firewall.nat_public_subnet,
    allowedTlsDomains: config.firewall.allowed_tls_domains,
    logRetentionDays: config.firewall.log_retention_days,
});
const logging = new LoggingComponent("logging", {
    ...common,
    region: config.region,
    vpcId: network.vpcId,
    retentionDays: config.logging.retention_days,
    flowLogRetentionDays: config.logging.flow_log_retention_days,
    forceDestroy: config.logging.force_destroy,
});
const dns = new Route53Component("dns", {
    ...common,
    zoneName: config.dns.zone_name,
});
const certificate = new AcmComponent("certificate", {
    ...common,
    domainName: config.dns.application_domain,
    zoneId: dns.zoneId,
    mode: config.dns.certificate_mode,
    importedCertificateArn: config.dns.imported_certificate_arn,
});
const database = new RdsComponent("database", {
    ...common,
    subnetIds: config.database.subnet_names.map(name => network.subnetIds[name]),
    securityGroupId: security.databaseSecurityGroupId,
    databaseName: config.database.name,
    port: config.database.port,
    engineVersion: config.database.engine_version,
    instanceClass: config.database.instance_class,
    allocatedStorageGiB: config.database.allocated_storage_gib,
    masterUsername: config.database.master_username,
    backupRetentionDays: config.database.backup_retention_days,
});
const identity = new IamComponent("identity", {
    ...common,
    applicationDatabaseSecretArn: database.applicationSecretArn,
});
const application = new EcsComponent("application", {
    ...common,
    region: config.region,
    vpcId: network.vpcId,
    applicationSubnetIds: config.application.subnet_names.map(name => network.subnetIds[name]),
    applicationRouteTableIds: config.application.subnet_names.map(name => network.routeTableIds[name]),
    publicSubnetIds: config.application.public_subnet_names.map(name => network.subnetIds[name]),
    albSecurityGroupId: security.albSecurityGroupId,
    taskSecurityGroupId: security.applicationSecurityGroupId,
    endpointSecurityGroupId: security.endpointSecurityGroupId,
    certificateArn: certificate.certificateArn,
    auditBucketName: logging.auditBucketName,
    databaseEndpoint: database.endpoint,
    applicationDatabaseSecretArn: database.applicationSecretArn,
    executionRoleArn: identity.executionRoleArn,
    taskRoleArn: identity.taskRoleArn,
    executionPolicy: identity.executionPolicy,
    applicationPort: config.application.app_port,
    healthCheckPath: config.application.health_check_path,
    desiredCount: config.application.desired_count,
    imageTag: config.application.image_tag,
    artifactUrl: config.application.artifact_url,
    artifactSha256: config.application.artifact_sha256,
    runtimeHttpsUrl: config.application.runtime_https_url,
    logRetentionDays: config.application.log_retention_days,
});
dns.addApplicationAlias({
    domain: config.dns.application_domain,
    albDnsName: application.albDnsName,
    albZoneId: application.albZoneId,
});
const waf = new WafComponent("waf", {
    ...common,
    loadBalancerArn: application.albArn,
    managedRuleGroups: config.security.waf_rules,
});
const guardDuty = new GuardDutyComponent("guardduty", {
    ...common,
    enabled: config.security.enable_guardduty,
});

export const vpcId = network.vpcId;
export const firewallArn = firewall.firewallArn;
export const cloudTrailArn = logging.cloudTrailArn;
export const rdsEndpoint = database.endpoint;
export const rdsMasterSecretArn = database.masterSecretArn;
export const applicationDatabaseSecretArn = database.applicationSecretArn;
export const albDnsName = application.albDnsName;
export const ecsClusterName = application.clusterName;
export const ecsServiceName = application.serviceName;
export const ecrRepositoryUrl = application.repositoryUrl;
export const wafArn = waf.aclArn;
export const guardDutyDetectorId = guardDuty.detectorId;
