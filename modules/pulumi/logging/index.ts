import * as aws from "@pulumi/aws";
import * as pulumi from "@pulumi/pulumi";
import {ComponentArgs, childOptions, componentOptions} from "../common";

export interface LoggingArgs extends ComponentArgs {
    vpcId: pulumi.Input<string>;
    retentionDays: number;
    flowLogRetentionDays: number;
    forceDestroy: boolean;
    region: string;
}

export class LoggingComponent extends pulumi.ComponentResource {
    readonly auditBucketName: pulumi.Output<string>;
    readonly auditBucketArn: pulumi.Output<string>;
    readonly cloudTrailArn: pulumi.Output<string>;
    readonly flowLogId: pulumi.Output<string>;

    constructor(name: string, args: LoggingArgs, opts?: pulumi.ComponentResourceOptions) {
        super("myorg:audit:Logging", name, {}, componentOptions(opts));
        const caller = aws.getCallerIdentityOutput();
        const trailName = `${args.namePrefix}-audit`;
        const bucket = new aws.s3.Bucket("audit", {
            bucket: pulumi.interpolate`${args.namePrefix}-${caller.accountId}-audit`,
            forceDestroy: args.forceDestroy,
            tags: args.tags,
        }, childOptions(this));
        new aws.s3.BucketPublicAccessBlock("audit-public-access", {
            bucket: bucket.id,
            blockPublicAcls: true,
            blockPublicPolicy: true,
            ignorePublicAcls: true,
            restrictPublicBuckets: true,
        }, childOptions(this));
        new aws.s3.BucketVersioning("audit-versioning", {
            bucket: bucket.id,
            versioningConfiguration: {status: "Enabled"},
        }, childOptions(this));
        new aws.s3.BucketServerSideEncryptionConfiguration("audit-sse", {
            bucket: bucket.id,
            rules: [{applyServerSideEncryptionByDefault: {sseAlgorithm: "AES256"}}],
        }, childOptions(this));
        new aws.s3.BucketLifecycleConfiguration("audit-retention", {
            bucket: bucket.id,
            rules: [{
                id: "expire-audit-data", status: "Enabled",
                filter: {prefix: ""},
                expiration: {days: args.retentionDays},
                noncurrentVersionExpiration: {noncurrentDays: args.retentionDays},
            }],
        }, childOptions(this));

        const bucketPolicy = new aws.s3.BucketPolicy("audit-delivery", {
            bucket: bucket.id,
            policy: pulumi.all([bucket.arn, caller.accountId]).apply(([arn, accountId]) => JSON.stringify({
                Version: "2012-10-17",
                Statement: [
                    {
                        Sid: "DenyInsecureTransport", Effect: "Deny",
                        Principal: "*", Action: "s3:*",
                        Resource: [arn, `${arn}/*`],
                        Condition: {Bool: {"aws:SecureTransport": "false"}},
                    },
                    {
                        Sid: "CloudTrailAclCheck", Effect: "Allow",
                        Principal: {Service: "cloudtrail.amazonaws.com"},
                        Action: "s3:GetBucketAcl", Resource: arn,
                        Condition: {StringEquals: {
                            "aws:SourceArn": `arn:aws:cloudtrail:${args.region}:${accountId}:trail/${trailName}`,
                        }},
                    },
                    {
                        Sid: "CloudTrailWrite", Effect: "Allow",
                        Principal: {Service: "cloudtrail.amazonaws.com"},
                        Action: "s3:PutObject",
                        Resource: `${arn}/cloudtrail/AWSLogs/${accountId}/*`,
                        Condition: {StringEquals: {
                            "s3:x-amz-acl": "bucket-owner-full-control",
                            "aws:SourceArn": `arn:aws:cloudtrail:${args.region}:${accountId}:trail/${trailName}`,
                        }},
                    },
                    {
                        Sid: "AlbLogDelivery", Effect: "Allow",
                        Principal: {Service: "logdelivery.elasticloadbalancing.amazonaws.com"},
                        Action: "s3:PutObject",
                        Resource: `${arn}/alb/AWSLogs/${accountId}/*`,
                    },
                ],
            })),
        }, childOptions(this));

        const trail = new aws.cloudtrail.Trail("regional-trail", {
            name: trailName,
            s3BucketName: bucket.id,
            s3KeyPrefix: "cloudtrail",
            includeGlobalServiceEvents: true,
            isMultiRegionTrail: false,
            enableLogFileValidation: true,
            tags: args.tags,
        }, {parent: this, dependsOn: [bucketPolicy]});

        const flowGroup = new aws.cloudwatch.LogGroup("vpc-flow-logs", {
            name: `/aws/vpc/flowlogs/${args.namePrefix}`,
            retentionInDays: args.flowLogRetentionDays,
            tags: args.tags,
        }, childOptions(this));
        const flowRole = new aws.iam.Role("vpc-flow-logs", {
            name: `${args.namePrefix}-flow-logs`,
            assumeRolePolicy: JSON.stringify({
                Version: "2012-10-17",
                Statement: [{Effect: "Allow", Action: "sts:AssumeRole", Principal: {Service: "vpc-flow-logs.amazonaws.com"}}],
            }),
            tags: args.tags,
        }, childOptions(this));
        const flowPolicy = new aws.iam.RolePolicy("vpc-flow-log-writer", {
            role: flowRole.name,
            policy: flowGroup.arn.apply(arn => JSON.stringify({
                Version: "2012-10-17",
                Statement: [{
                    Effect: "Allow",
                    Action: ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"],
                    Resource: `${arn}:*`,
                }],
            })),
        }, childOptions(this));
        const flowLog = new aws.ec2.FlowLog("vpc", {
            vpcId: args.vpcId,
            trafficType: "ALL",
            logDestinationType: "cloud-watch-logs",
            logDestination: flowGroup.arn,
            iamRoleArn: flowRole.arn,
            tags: args.tags,
        }, {parent: this, dependsOn: [flowPolicy]});

        this.auditBucketName = bucket.bucket;
        this.auditBucketArn = bucket.arn;
        this.cloudTrailArn = trail.arn;
        this.flowLogId = flowLog.id;
        this.registerOutputs({auditBucketName: bucket.bucket, cloudTrailArn: trail.arn, flowLogId: flowLog.id});
    }
}
