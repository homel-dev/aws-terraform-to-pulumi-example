import * as aws from "@pulumi/aws";
import * as pulumi from "@pulumi/pulumi";
import {ComponentArgs, childOptions, componentOptions} from "../common";

export interface RdsArgs extends ComponentArgs {
    subnetIds: pulumi.Input<string>[];
    securityGroupId: pulumi.Input<string>;
    databaseName: string;
    port: number;
    engineVersion: string;
    instanceClass: string;
    allocatedStorageGiB: number;
    masterUsername: string;
    backupRetentionDays: number;
}

export class RdsComponent extends pulumi.ComponentResource {
    readonly endpoint: pulumi.Output<string>;
    readonly identifier: pulumi.Output<string>;
    readonly masterSecretArn: pulumi.Output<string>;
    readonly applicationSecretArn: pulumi.Output<string>;

    constructor(name: string, args: RdsArgs, opts?: pulumi.ComponentResourceOptions) {
        super("myorg:database:Rds", name, {}, componentOptions(opts));
        const subnetGroup = new aws.rds.SubnetGroup("database", {
            name: `${args.namePrefix}-db-subnets`,
            subnetIds: args.subnetIds,
            tags: args.tags,
        }, childOptions(this));
        const database = new aws.rds.Instance("mysql", {
            identifier: `${args.namePrefix}-mysql`,
            engine: "mysql",
            engineVersion: args.engineVersion,
            instanceClass: args.instanceClass,
            allocatedStorage: args.allocatedStorageGiB,
            storageType: "gp3",
            storageEncrypted: true,
            dbName: args.databaseName,
            username: args.masterUsername,
            manageMasterUserPassword: true,
            port: args.port,
            dbSubnetGroupName: subnetGroup.name,
            vpcSecurityGroupIds: [args.securityGroupId],
            publiclyAccessible: false,
            multiAz: true,
            backupRetentionPeriod: args.backupRetentionDays,
            copyTagsToSnapshot: true,
            deletionProtection: true,
            skipFinalSnapshot: false,
            finalSnapshotIdentifier: `${args.namePrefix}-mysql-final`,
            tags: args.tags,
        }, childOptions(this));

        // Metadata only. An authorized operator must populate a least-privilege
        // application credential after migration; no password enters Pulumi.
        const applicationSecret = new aws.secretsmanager.Secret("application-database-credential", {
            name: `${args.namePrefix}/application-database`,
            recoveryWindowInDays: 7,
            tags: args.tags,
        }, childOptions(this));

        this.endpoint = database.endpoint;
        this.identifier = database.identifier;
        this.masterSecretArn = database.masterUserSecrets.apply(secrets => secrets[0]?.secretArn ?? "");
        this.applicationSecretArn = applicationSecret.arn;
        this.registerOutputs({
            endpoint: this.endpoint, identifier: this.identifier,
            masterSecretArn: this.masterSecretArn,
            applicationSecretArn: this.applicationSecretArn,
        });
    }
}
