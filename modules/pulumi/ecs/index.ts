import * as aws from "@pulumi/aws";
import * as pulumi from "@pulumi/pulumi";
import {ComponentArgs, childOptions, componentOptions} from "../common";

export interface EcsArgs extends ComponentArgs {
    region: string;
    vpcId: pulumi.Input<string>;
    applicationSubnetIds: pulumi.Input<string>[];
    applicationRouteTableIds: pulumi.Input<string>[];
    publicSubnetIds: pulumi.Input<string>[];
    albSecurityGroupId: pulumi.Input<string>;
    taskSecurityGroupId: pulumi.Input<string>;
    endpointSecurityGroupId: pulumi.Input<string>;
    certificateArn: pulumi.Input<string>;
    auditBucketName: pulumi.Input<string>;
    databaseEndpoint: pulumi.Input<string>;
    applicationDatabaseSecretArn: pulumi.Input<string>;
    executionRoleArn: pulumi.Input<string>;
    taskRoleArn: pulumi.Input<string>;
    executionPolicy: aws.iam.RolePolicyAttachment;
    applicationPort: number;
    healthCheckPath: string;
    desiredCount: number;
    imageTag: string;
    artifactUrl: string;
    artifactSha256: string;
    runtimeHttpsUrl: string;
    logRetentionDays: number;
}

export class EcsComponent extends pulumi.ComponentResource {
    readonly albDnsName: pulumi.Output<string>;
    readonly albZoneId: pulumi.Output<string>;
    readonly albArn: pulumi.Output<string>;
    readonly clusterName: pulumi.Output<string>;
    readonly serviceName: pulumi.Output<string>;
    readonly repositoryUrl: pulumi.Output<string>;

    constructor(name: string, args: EcsArgs, opts?: pulumi.ComponentResourceOptions) {
        super("myorg:compute:EcsFargate", name, {}, componentOptions(opts));
        const repository = new aws.ecr.Repository("application", {
            name: `${args.namePrefix}-application`,
            imageTagMutability: "IMMUTABLE",
            imageScanningConfiguration: {scanOnPush: true},
            encryptionConfigurations: [{encryptionType: "AES256"}],
            forceDelete: false,
            tags: args.tags,
        }, childOptions(this));
        const logGroup = new aws.cloudwatch.LogGroup("application", {
            name: `/aws/ecs/${args.namePrefix}`,
            retentionInDays: args.logRetentionDays,
            tags: args.tags,
        }, childOptions(this));
        const cluster = new aws.ecs.Cluster("application", {
            name: args.namePrefix,
            settings: [{name: "containerInsights", value: "enabled"}],
            tags: args.tags,
        }, childOptions(this));

        const endpointServices = ["ecr.api", "ecr.dkr", "logs", "secretsmanager"];
        const endpoints = endpointServices.map(service => new aws.ec2.VpcEndpoint(
            `endpoint-${service.replace(".", "-")}`, {
                vpcId: args.vpcId,
                vpcEndpointType: "Interface",
                serviceName: `com.amazonaws.${args.region}.${service}`,
                privateDnsEnabled: true,
                subnetIds: args.applicationSubnetIds,
                securityGroupIds: [args.endpointSecurityGroupId],
                tags: args.tags,
            }, childOptions(this),
        ));
        const s3Endpoint = new aws.ec2.VpcEndpoint("endpoint-s3", {
            vpcId: args.vpcId,
            vpcEndpointType: "Gateway",
            serviceName: `com.amazonaws.${args.region}.s3`,
            routeTableIds: args.applicationRouteTableIds,
            tags: args.tags,
        }, childOptions(this));

        const task = new aws.ecs.TaskDefinition("application", {
            family: args.namePrefix,
            requiresCompatibilities: ["FARGATE"],
            networkMode: "awsvpc",
            cpu: "256",
            memory: "512",
            executionRoleArn: args.executionRoleArn,
            taskRoleArn: args.taskRoleArn,
            runtimePlatform: {cpuArchitecture: "X86_64", operatingSystemFamily: "LINUX"},
            containerDefinitions: pulumi.all([
                repository.repositoryUrl, logGroup.name,
                args.databaseEndpoint, args.applicationDatabaseSecretArn,
            ]).apply(([imageRepo, logName, dbEndpoint, secretArn]) => JSON.stringify([{
                name: "app",
                image: `${imageRepo}:${args.imageTag}`,
                essential: true,
                readonlyRootFilesystem: false, // external artifact written only at task start
                portMappings: [{containerPort: args.applicationPort, hostPort: args.applicationPort, protocol: "tcp"}],
                environment: [
                    {name: "MYORG_APP_PORT", value: String(args.applicationPort)},
                    {name: "ARTIFACT_URL", value: args.artifactUrl},
                    {name: "ARTIFACT_SHA256", value: args.artifactSha256},
                    {name: "MYORG_DATABASE_SECRET", value: secretArn},
                    {name: "MYORG_DB_ENDPOINT", value: dbEndpoint},
                    {name: "MYORG_RUNTIME_HTTPS_URL", value: args.runtimeHttpsUrl},
                ],
                logConfiguration: {
                    logDriver: "awslogs",
                    options: {
                        "awslogs-group": logName,
                        "awslogs-region": args.region,
                        "awslogs-stream-prefix": "app",
                    },
                },
            }])),
            tags: args.tags,
        }, {parent: this, dependsOn: [args.executionPolicy]});

        const alb = new aws.lb.LoadBalancer("application", {
            name: `${args.namePrefix}-app`,
            loadBalancerType: "application",
            internal: false,
            securityGroups: [args.albSecurityGroupId],
            subnets: args.publicSubnetIds,
            dropInvalidHeaderFields: true,
            accessLogs: {bucket: args.auditBucketName, prefix: "alb", enabled: true},
            tags: args.tags,
        }, childOptions(this));
        const targetGroup = new aws.lb.TargetGroup("application", {
            name: `${args.namePrefix}-app`,
            vpcId: args.vpcId,
            targetType: "ip",
            port: args.applicationPort,
            protocol: "HTTP",
            healthCheck: {
                path: args.healthCheckPath,
                matcher: "200-399",
                healthyThreshold: 2,
                unhealthyThreshold: 3,
                timeout: 5,
                interval: 15,
            },
            tags: args.tags,
        }, childOptions(this));
        const https = new aws.lb.Listener("https", {
            loadBalancerArn: alb.arn,
            port: 443,
            protocol: "HTTPS",
            certificateArn: args.certificateArn,
            sslPolicy: "ELBSecurityPolicy-TLS13-1-2-2021-06",
            defaultActions: [{type: "forward", targetGroupArn: targetGroup.arn}],
            tags: args.tags,
        }, childOptions(this));

        const service = new aws.ecs.Service("application", {
            name: args.namePrefix,
            cluster: cluster.arn,
            taskDefinition: task.arn,
            desiredCount: args.desiredCount,
            launchType: "FARGATE",
            platformVersion: "LATEST",
            enableExecuteCommand: false,
            networkConfiguration: {
                subnets: args.applicationSubnetIds,
                securityGroups: [args.taskSecurityGroupId],
                assignPublicIp: false,
            },
            loadBalancers: [{
                targetGroupArn: targetGroup.arn,
                containerName: "app",
                containerPort: args.applicationPort,
            }],
            healthCheckGracePeriodSeconds: 120,
            waitForSteadyState: false,
            tags: args.tags,
        }, {parent: this, dependsOn: [https, s3Endpoint, ...endpoints]});

        this.albDnsName = alb.dnsName;
        this.albZoneId = alb.zoneId;
        this.albArn = alb.arn;
        this.clusterName = cluster.name;
        this.serviceName = service.name;
        this.repositoryUrl = repository.repositoryUrl;
        this.registerOutputs({
            albDnsName: this.albDnsName,
            albArn: this.albArn,
            clusterName: this.clusterName,
            serviceName: this.serviceName,
            repositoryUrl: this.repositoryUrl,
        });
    }
}
