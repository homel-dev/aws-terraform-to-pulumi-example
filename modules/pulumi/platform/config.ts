import * as fs from "node:fs";
import * as path from "node:path";
import * as pulumi from "@pulumi/pulumi";
import YAML from "yaml";

export interface SubnetConfig {
    type: "public" | "application" | "database" | "firewall";
    availability_zone: string;
    cidr: string;
}

export interface VpcConfig {
    name: string;
    cidr: string;
    subnets: Record<string, SubnetConfig>;
    tags: Record<string, string>;
}

export interface FirewallConfig {
    name: string;
    application_subnet: string;
    firewall_subnet: string;
    nat_public_subnet: string;
    allowed_tls_domains: string[];
    log_retention_days: number;
}

export interface LoggingConfig {
    retention_days: number;
    flow_log_retention_days: number;
    force_destroy: boolean;
}

export interface DatabaseConfig {
    name: string;
    port: number;
    subnet_names: string[];
    engine_version: string;
    instance_class: string;
    allocated_storage_gib: number;
    master_username: string;
    backup_retention_days: number;
}

export interface ApplicationConfig {
    subnet_names: string[];
    public_subnet_names: string[];
    app_port: number;
    health_check_path: string;
    desired_count: number;
    image_tag: string;
    artifact_url: string;
    artifact_sha256: string;
    runtime_https_url: string;
    log_retention_days: number;
}

export interface DnsConfig {
    zone_name: string;
    application_domain: string;
    certificate_mode: "managed_dns" | "imported";
    imported_certificate_arn?: string;
}

export interface SecurityConfig {
    approved_ingress_cidrs: string[];
    enable_guardduty: boolean;
    waf_rules: string[];
}

export interface EnvironmentConfig {
    region: string;
    vpc: VpcConfig;
    firewall: FirewallConfig;
    logging: LoggingConfig;
    database: DatabaseConfig;
    application: ApplicationConfig;
    dns: DnsConfig;
    security: SecurityConfig;
}

export function loadEnvironment(): EnvironmentConfig {
    const configDir = path.join(pulumi.runtime.getRootDirectory(), "config");
    const read = <T>(filename: string): T => YAML.parse(
        fs.readFileSync(path.join(configDir, filename), "utf8"),
    ) as T;

    return {
        region: read<{region: string}>("location.yml").region,
        vpc: read<VpcConfig>("vpc.yml"),
        firewall: read<FirewallConfig>("firewall.yml"),
        logging: read<LoggingConfig>("logging.yml"),
        database: read<DatabaseConfig>("database.yml"),
        application: read<ApplicationConfig>("application.yml"),
        dns: read<DnsConfig>("dns.yml"),
        security: read<SecurityConfig>("security.yml"),
    };
}
