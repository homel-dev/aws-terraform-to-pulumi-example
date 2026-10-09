import * as aws from "@pulumi/aws";
import * as pulumi from "@pulumi/pulumi";
import {ComponentArgs, childOptions, componentOptions} from "../common";

export interface WafArgs extends ComponentArgs {
    loadBalancerArn: pulumi.Input<string>;
    managedRuleGroups: string[];
}

export class WafComponent extends pulumi.ComponentResource {
    readonly aclArn: pulumi.Output<string>;

    constructor(name: string, args: WafArgs, opts?: pulumi.ComponentResourceOptions) {
        super("myorg:security:Waf", name, {}, componentOptions(opts));
        const acl = new aws.wafv2.WebAcl("application", {
            name: `${args.namePrefix}-alb`,
            scope: "REGIONAL",
            defaultAction: {allow: {}},
            rules: args.managedRuleGroups.map((group, index) => ({
                name: group,
                priority: (index + 1) * 10,
                overrideAction: {none: {}},
                statement: {managedRuleGroupStatement: {name: group, vendorName: "AWS"}},
                visibilityConfig: {
                    cloudwatchMetricsEnabled: true,
                    metricName: `${args.namePrefix}-managed-${index}`,
                    sampledRequestsEnabled: true,
                },
            })),
            visibilityConfig: {
                cloudwatchMetricsEnabled: true,
                metricName: `${args.namePrefix}-alb`,
                sampledRequestsEnabled: true,
            },
            tags: args.tags,
        }, childOptions(this));
        new aws.wafv2.WebAclAssociation("application", {
            resourceArn: args.loadBalancerArn,
            webAclArn: acl.arn,
        }, childOptions(this));
        this.aclArn = acl.arn;
        this.registerOutputs({aclArn: this.aclArn});
    }
}
