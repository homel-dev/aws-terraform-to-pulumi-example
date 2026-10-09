import * as aws from "@pulumi/aws";
import * as pulumi from "@pulumi/pulumi";
import {ComponentArgs, childOptions, componentOptions} from "../common";

export interface SecurityArgs extends ComponentArgs {
    vpcId: pulumi.Input<string>;
    applicationPort: number;
    databasePort: number;
    approvedIngressCidrs: string[];
}

export class SecurityComponent extends pulumi.ComponentResource {
    readonly albSecurityGroupId: pulumi.Output<string>;
    readonly applicationSecurityGroupId: pulumi.Output<string>;
    readonly databaseSecurityGroupId: pulumi.Output<string>;
    readonly endpointSecurityGroupId: pulumi.Output<string>;

    constructor(name: string, args: SecurityArgs, opts?: pulumi.ComponentResourceOptions) {
        super("myorg:security:Boundary", name, {}, componentOptions(opts));
        const sg = (id: string, description: string) => new aws.ec2.SecurityGroup(id, {
            vpcId: args.vpcId,
            description,
            name: `${args.namePrefix}-${id}`,
            tags: args.tags,
        }, childOptions(this));
        const alb = sg("alb", "Only approved client HTTPS requests");
        const app = sg("app", "Private ECS/Fargate application");
        const db = sg("rds", "Private RDS MySQL");
        const endpoints = sg("endpoints", "Private AWS service endpoints");

        const allow = (key: string, source: pulumi.Input<string>, target: pulumi.Input<string>, port: number) => {
            new aws.vpc.SecurityGroupIngressRule(`${key}-ingress`, {
                securityGroupId: target, referencedSecurityGroupId: source,
                ipProtocol: "tcp", fromPort: port, toPort: port, tags: args.tags,
            }, childOptions(this));
            new aws.vpc.SecurityGroupEgressRule(`${key}-egress`, {
                securityGroupId: source, referencedSecurityGroupId: target,
                ipProtocol: "tcp", fromPort: port, toPort: port, tags: args.tags,
            }, childOptions(this));
        };

        args.approvedIngressCidrs.forEach((cidr, index) => new aws.vpc.SecurityGroupIngressRule(
            `approved-https-${index}`, {
                securityGroupId: alb.id, cidrIpv4: cidr,
                ipProtocol: "tcp", fromPort: 443, toPort: 443, tags: args.tags,
            }, childOptions(this),
        ));
        allow("alb-to-app", alb.id, app.id, args.applicationPort);
        allow("app-to-db", app.id, db.id, args.databasePort);
        allow("app-to-aws-endpoints", app.id, endpoints.id, 443);

        // The route table + Network Firewall policy, not the security group,
        // constrains public HTTPS by hostname / TLS SNI.
        new aws.vpc.SecurityGroupEgressRule("app-https-via-firewall", {
            securityGroupId: app.id, cidrIpv4: "0.0.0.0/0",
            ipProtocol: "tcp", fromPort: 443, toPort: 443, tags: args.tags,
        }, childOptions(this));

        this.albSecurityGroupId = alb.id;
        this.applicationSecurityGroupId = app.id;
        this.databaseSecurityGroupId = db.id;
        this.endpointSecurityGroupId = endpoints.id;
        this.registerOutputs({
            albSecurityGroupId: alb.id, applicationSecurityGroupId: app.id,
            databaseSecurityGroupId: db.id, endpointSecurityGroupId: endpoints.id,
        });
    }
}
