import * as aws from "@pulumi/aws";
import * as pulumi from "@pulumi/pulumi";

// Terraform retains ownership of VPC, RDS, WAF, audit bucket and the old ALB.
// This stack creates new, separately owned ECS resources; it never cuts over
// the existing production listener, DNS record or database.
const cfg = new pulumi.Config();
const awsCfg = new pulumi.Config("aws");
if (awsCfg.require("region") !== "us-east-1") {
    throw new Error("This POC is scoped to us-east-1 only");
}

const vpcId = cfg.require("vpcId");
const appSubnetIds = cfg.requireObject<string[]>("appSubnetIds");
const appRouteTableIds = cfg.requireObject<string[]>("appRouteTableIds");
const publicSubnetIds = cfg.requireObject<string[]>("publicSubnetIds");
const ingressCidrs = cfg.requireObject<string[]>("ingressCidrs");
const certificateArn = cfg.require("certificateArn");
const auditBucketName = cfg.require("auditBucketName");
const rdsSecurityGroupId = cfg.require("rdsSecurityGroupId");
const databaseSecretArn = cfg.require("databaseSecretArn");
const rdsEndpoint = cfg.require("rdsEndpoint");
const endpointSecurityGroupId = cfg.require("endpointSecurityGroupId");
const wafAclArn = cfg.require("wafAclArn");
const artifactUrl = cfg.require("artifactUrl");
const artifactSha256 = cfg.get("artifactSha256") || "";
const runtimeHttpsUrl = cfg.require("runtimeHttpsUrl");
const imageTag = cfg.require("imageTag");
const desiredCount = cfg.getNumber("desiredCount") ?? 0;

if (
    appSubnetIds.length === 0 || appRouteTableIds.length === 0 ||
    publicSubnetIds.length < 2 || ingressCidrs.length === 0 ||
    !artifactUrl.startsWith("https://") || !runtimeHttpsUrl.startsWith("https://") ||
    !/^[a-zA-Z0-9_.-]+$/.test(imageTag) ||
    (artifactSha256 !== "" && !/^[a-fA-F0-9]{64}$/.test(artifactSha256)) ||
    !Number.isInteger(desiredCount) || desiredCount < 0 || desiredCount > 2
) {
    throw new Error("Invalid network, HTTPS artifact, image tag, digest or desiredCount configuration");
}

const name = "myorg-poc-use1-ecs";
const tags = {
    Project: "myorg-aws-poc",
    Purpose: "pci-dss-network-control",
    BusinessUnit: "myorg",
    Environment: "poc",
    Location: "use1",
    ManagedBy: "Pulumi",
    Stack: "ecs",
};

// SG resources contain no inline rules: Pulumi owns only the rules declared
// below. The RDS and existing Secrets Manager endpoint SGs remain in Terraform.
function securityGroup(id: string, description: string): aws.ec2.SecurityGroup {
    return new aws.ec2.SecurityGroup(id, {
        name: `${name}-${id}`,
        description,
        vpcId,
        tags,
    });
}

function ingress(
    id: string, target: pulumi.Input<string>, source: pulumi.Input<string>, port: number,
): aws.vpc.SecurityGroupIngressRule {
    return new aws.vpc.SecurityGroupIngressRule(id, {
        securityGroupId: target,
        referencedSecurityGroupId: source,
        ipProtocol: "tcp",
        fromPort: port,
        toPort: port,
        tags,
    });
}

function egress(
    id: string, source: pulumi.Input<string>, target: pulumi.Input<string>, port: number,
): aws.vpc.SecurityGroupEgressRule {
    return new aws.vpc.SecurityGroupEgressRule(id, {
        securityGroupId: source,
        referencedSecurityGroupId: target,
        ipProtocol: "tcp",
        fromPort: port,
        toPort: port,
        tags,
    });
}

const albSg = securityGroup("alb", "Modernized HTTPS ALB; approved ingress only");
const taskSg = securityGroup("task", "Private Fargate application tasks");
const awsEndpointSg = securityGroup("aws-endpoints", "ECR and CloudWatch private endpoints");

ingressCidrs.forEach((cidr, index) => {
    new aws.vpc.SecurityGroupIngressRule(`approved-https-${index}`, {
        securityGroupId: albSg.id,
        cidrIpv4: cidr,
        ipProtocol: "tcp",
        fromPort: 443,
        toPort: 443,
        description: "IN-01: approved HTTPS client",
        tags,
    });
});

egress("alb-to-task", albSg.id, taskSg.id, 8080);
ingress("task-from-alb", taskSg.id, albSg.id, 8080);
egress("task-to-rds", taskSg.id, rdsSecurityGroupId, 3306);
ingress("rds-from-task", rdsSecurityGroupId, taskSg.id, 3306);

// Runtime HTTPS follows the existing application subnet's Network Firewall
// route and SNI allowlist. An SG alone is not a hostname egress filter.
new aws.vpc.SecurityGroupEgressRule("task-https-via-firewall", {
    securityGroupId: taskSg.id,
    cidrIpv4: "0.0.0.0/0",
    ipProtocol: "tcp",
    fromPort: 443,
    toPort: 443,
    description: "HTTPS routed through existing Network Firewall",
    tags,
});

egress("task-to-aws-endpoints", taskSg.id, awsEndpointSg.id, 443);
ingress("aws-endpoints-from-task", awsEndpointSg.id, taskSg.id, 443);
egress("task-to-secrets-endpoint", taskSg.id, endpointSecurityGroupId, 443);
const existingSecretsEndpointIngress = ingress(
    "secrets-endpoint-from-task", endpointSecurityGroupId, taskSg.id, 443,
);

// Fargate image pulls and awslogs cannot rely on Internet egress through the
// domain-limited Network Firewall. Each interface endpoint adds hourly cost.
const endpointServices = ["ecr.api", "ecr.dkr", "logs"] as const;
const interfaceEndpoints = endpointServices.map(service => new aws.ec2.VpcEndpoint(
    `endpoint-${service.replace(".", "-")}`,
    {
        vpcId,
        vpcEndpointType: "Interface",
        serviceName: `com.amazonaws.us-east-1.${service}`,
        privateDnsEnabled: true,
        subnetIds: appSubnetIds,
        securityGroupIds: [awsEndpointSg.id],
        tags,
    },
));
const s3Endpoint = new aws.ec2.VpcEndpoint("endpoint-s3", {
    vpcId,
    vpcEndpointType: "Gateway",
    serviceName: "com.amazonaws.us-east-1.s3",
    routeTableIds: appRouteTableIds,
    tags,
});

const repository = new aws.ecr.Repository("application", {
    name: `${name}-application`,
    imageTagMutability: "IMMUTABLE",
    imageScanningConfiguration: {scanOnPush: true},
    encryptionConfigurations: [{encryptionType: "AES256"}],
    forceDelete: false,
    tags,
});
const logGroup = new aws.cloudwatch.LogGroup("application", {
    name: `/aws/ecs/${name}`,
    retentionInDays: 30,
    tags,
});
const cluster = new aws.ecs.Cluster("application", {
    name,
    settings: [{name: "containerInsights", value: "enabled"}],
    tags,
});

const ecsAssumeRole = JSON.stringify({
    Version: "2012-10-17",
    Statement: [{
        Effect: "Allow",
        Principal: {Service: "ecs-tasks.amazonaws.com"},
        Action: "sts:AssumeRole",
    }],
});
const executionRole = new aws.iam.Role("execution-role", {
    name: `${name}-execution`,
    assumeRolePolicy: ecsAssumeRole,
    tags,
});
const executionPolicy = new aws.iam.RolePolicyAttachment("execution-policy", {
    role: executionRole.name,
    policyArn: "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy",
});
const taskRole = new aws.iam.Role("task-role", {
    name: `${name}-task`,
    assumeRolePolicy: ecsAssumeRole,
    tags,
});
new aws.iam.RolePolicy("task-database-secret", {
    role: taskRole.name,
    policy: JSON.stringify({
        Version: "2012-10-17",
        Statement: [{
            Effect: "Allow",
            Action: ["secretsmanager:GetSecretValue"],
            Resource: databaseSecretArn,
        }],
    }),
});

const taskDefinition = new aws.ecs.TaskDefinition("application", {
    family: name,
    networkMode: "awsvpc",
    requiresCompatibilities: ["FARGATE"],
    cpu: "256",
    memory: "512",
    executionRoleArn: executionRole.arn,
    taskRoleArn: taskRole.arn,
    runtimePlatform: {cpuArchitecture: "X86_64", operatingSystemFamily: "LINUX"},
    containerDefinitions: pulumi.all([repository.repositoryUrl, logGroup.name]).apply(
        ([repositoryUrl, logGroupName]) => JSON.stringify([{
            name: "app",
            image: `${repositoryUrl}:${imageTag}`,
            essential: true,
            readonlyRootFilesystem: false, // artifact is downloaded at startup, not baked in
            portMappings: [{containerPort: 8080, hostPort: 8080, protocol: "tcp"}],
            environment: [
                {name: "ARTIFACT_URL", value: artifactUrl},
                {name: "ARTIFACT_SHA256", value: artifactSha256},
                {name: "MYORG_DATABASE_SECRET", value: databaseSecretArn},
                {name: "MYORG_DB_ENDPOINT", value: rdsEndpoint},
                {name: "MYORG_RUNTIME_HTTPS_URL", value: runtimeHttpsUrl},
            ],
            logConfiguration: {
                logDriver: "awslogs",
                options: {
                    "awslogs-group": logGroupName,
                    "awslogs-region": "us-east-1",
                    "awslogs-stream-prefix": "app",
                },
            },
        }]),
    ),
    tags,
}, {dependsOn: executionPolicy});

// A second ALB avoids dual Terraform/Pulumi ownership of the original
// listener/target group and makes cutover an explicit later decision.
const alb = new aws.lb.LoadBalancer("application", {
    name: name,
    loadBalancerType: "application",
    internal: false,
    securityGroups: [albSg.id],
    subnets: publicSubnetIds,
    dropInvalidHeaderFields: true,
    accessLogs: {bucket: auditBucketName, prefix: "alb", enabled: true},
    tags,
});
const targetGroup = new aws.lb.TargetGroup("application", {
    name,
    targetType: "ip", // mandatory for Fargate/awsvpc
    vpcId,
    port: 8080,
    protocol: "HTTP",
    healthCheck: {
        enabled: true,
        path: "/",
        matcher: "200-399",
        healthyThreshold: 2,
        unhealthyThreshold: 3,
        interval: 15,
    },
    tags,
});
const httpsListener = new aws.lb.Listener("https", {
    loadBalancerArn: alb.arn,
    port: 443,
    protocol: "HTTPS",
    sslPolicy: "ELBSecurityPolicy-TLS13-1-2-2021-06",
    certificateArn,
    defaultActions: [{type: "forward", targetGroupArn: targetGroup.arn}],
    tags,
});
new aws.wafv2.WebAclAssociation("existing-waf", {
    resourceArn: alb.arn,
    webAclArn: wafAclArn,
});

const service = new aws.ecs.Service("application", {
    name,
    cluster: cluster.arn,
    taskDefinition: taskDefinition.arn,
    desiredCount,
    launchType: "FARGATE",
    platformVersion: "LATEST",
    enableExecuteCommand: false,
    networkConfiguration: {
        subnets: appSubnetIds,
        securityGroups: [taskSg.id],
        assignPublicIp: false,
    },
    loadBalancers: [{
        targetGroupArn: targetGroup.arn,
        containerName: "app",
        containerPort: 8080,
    }],
    healthCheckGracePeriodSeconds: 120,
    waitForSteadyState: false,
    tags,
}, {dependsOn: [httpsListener, s3Endpoint, existingSecretsEndpointIngress, ...interfaceEndpoints]});

export const albDnsName = alb.dnsName;
export const albArn = alb.arn;
export const ecsClusterName = cluster.name;
export const ecsServiceName = service.name;
export const ecrRepositoryUrl = repository.repositoryUrl;
export const ecsTargetGroupArn = targetGroup.arn;
