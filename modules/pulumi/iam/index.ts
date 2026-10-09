import * as aws from "@pulumi/aws";
import * as pulumi from "@pulumi/pulumi";
import {ComponentArgs, childOptions, componentOptions} from "../common";

export interface IamArgs extends ComponentArgs {
    applicationDatabaseSecretArn: pulumi.Input<string>;
}

export class IamComponent extends pulumi.ComponentResource {
    readonly executionRoleArn: pulumi.Output<string>;
    readonly taskRoleArn: pulumi.Output<string>;
    readonly executionPolicy: aws.iam.RolePolicyAttachment;

    constructor(name: string, args: IamArgs, opts?: pulumi.ComponentResourceOptions) {
        super("myorg:identity:EcsRoles", name, {}, componentOptions(opts));
        const assume = JSON.stringify({
            Version: "2012-10-17",
            Statement: [{Effect: "Allow", Action: "sts:AssumeRole", Principal: {Service: "ecs-tasks.amazonaws.com"}}],
        });
        const executionRole = new aws.iam.Role("execution", {
            name: `${args.namePrefix}-ecs-execution`,
            assumeRolePolicy: assume,
            tags: args.tags,
        }, childOptions(this));
        this.executionPolicy = new aws.iam.RolePolicyAttachment("ecs-execution-policy", {
            role: executionRole.name,
            policyArn: "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy",
        }, childOptions(this));
        const taskRole = new aws.iam.Role("task", {
            name: `${args.namePrefix}-ecs-task`,
            assumeRolePolicy: assume,
            tags: args.tags,
        }, childOptions(this));
        new aws.iam.RolePolicy("application-secret-read", {
            role: taskRole.name,
            policy: pulumi.output(args.applicationDatabaseSecretArn).apply(secretArn => JSON.stringify({
                Version: "2012-10-17",
                Statement: [{
                    Effect: "Allow",
                    Action: ["secretsmanager:GetSecretValue"],
                    Resource: secretArn,
                }],
            })),
        }, childOptions(this));

        this.executionRoleArn = executionRole.arn;
        this.taskRoleArn = taskRole.arn;
        this.registerOutputs({executionRoleArn: executionRole.arn, taskRoleArn: taskRole.arn});
    }
}
