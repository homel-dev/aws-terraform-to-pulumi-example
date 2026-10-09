import * as aws from "@pulumi/aws";
import * as pulumi from "@pulumi/pulumi";
import {ComponentArgs, childOptions, componentOptions} from "../common";

export interface FirewallArgs extends ComponentArgs {
    vpcId: pulumi.Input<string>;
    internetGateway: aws.ec2.InternetGateway;
    subnetIds: Record<string, pulumi.Input<string>>;
    subnetCidrs: Record<string, string>;
    routeTableIds: Record<string, pulumi.Input<string>>;
    applicationSubnet: string;
    firewallSubnet: string;
    natPublicSubnet: string;
    allowedTlsDomains: string[];
    logRetentionDays: number;
}

export class FirewallComponent extends pulumi.ComponentResource {
    readonly firewallArn: pulumi.Output<string>;
    readonly natGatewayId: pulumi.Output<string>;

    constructor(name: string, args: FirewallArgs, opts?: pulumi.ComponentResourceOptions) {
        super("myorg:network:Firewall", name, {}, componentOptions(opts));
        const rules = new aws.networkfirewall.RuleGroup("tls-allowlist", {
            name: `${args.namePrefix}-tls-allowlist`,
            capacity: 100,
            type: "STATEFUL",
            ruleGroup: {
                rulesSource: {rulesSourceList: {
                    generatedRulesType: "ALLOWLIST",
                    targetTypes: ["TLS_SNI"],
                    targets: args.allowedTlsDomains,
                }},
            },
            tags: args.tags,
        }, childOptions(this));

        const policy = new aws.networkfirewall.FirewallPolicy("egress-policy", {
            name: `${args.namePrefix}-egress`,
            firewallPolicy: {
                statelessDefaultActions: ["aws:forward_to_sfe"],
                statelessFragmentDefaultActions: ["aws:forward_to_sfe"],
                statefulRuleGroupReferences: [{resourceArn: rules.arn}],
            },
            tags: args.tags,
        }, childOptions(this));

        const firewall = new aws.networkfirewall.Firewall("egress", {
            name: `${args.namePrefix}-egress`,
            firewallPolicyArn: policy.arn,
            vpcId: args.vpcId,
            subnetMappings: [{subnetId: args.subnetIds[args.firewallSubnet]}],
            tags: args.tags,
        }, childOptions(this));

        const logGroup = new aws.cloudwatch.LogGroup("firewall-logs", {
            name: `/aws/network-firewall/${args.namePrefix}`,
            retentionInDays: args.logRetentionDays,
            tags: args.tags,
        }, childOptions(this));
        new aws.networkfirewall.LoggingConfiguration("firewall-logging", {
            firewallArn: firewall.arn,
            loggingConfiguration: {logDestinationConfigs: [
                {logDestination: {logGroup: logGroup.name}, logDestinationType: "CloudWatchLogs", logType: "ALERT"},
                {logDestination: {logGroup: logGroup.name}, logDestinationType: "CloudWatchLogs", logType: "FLOW"},
            ]},
        }, childOptions(this));

        const eip = new aws.ec2.Eip("nat-eip", {
            domain: "vpc",
            tags: args.tags,
        }, childOptions(this));
        const nat = new aws.ec2.NatGateway("nat", {
            allocationId: eip.id,
            subnetId: args.subnetIds[args.natPublicSubnet],
            tags: args.tags,
        }, {parent: this, dependsOn: [args.internetGateway]});

        // Network Firewall creates a regional endpoint per mapped subnet.
        // This one-AZ POC routes app-a through the matching endpoint and NAT.
        const endpointId = pulumi.all([firewall.firewallStatuses, args.subnetIds[args.firewallSubnet]])
            .apply(([states, subnetId]) => {
                const attachments = states.flatMap(state => state.syncStates ?? [])
                    .flatMap(sync => sync.attachments ?? []);
                const endpoint = attachments.find(a => a.subnetId === subnetId);
                if (!endpoint) {
                    throw new Error(`Firewall endpoint for subnet ${subnetId} is unavailable`);
                }
                return endpoint.endpointId;
            });
        new aws.ec2.Route("application-default-via-firewall", {
            routeTableId: args.routeTableIds[args.applicationSubnet],
            destinationCidrBlock: "0.0.0.0/0",
            vpcEndpointId: endpointId,
        }, childOptions(this));
        new aws.ec2.Route("firewall-default-via-nat", {
            routeTableId: args.routeTableIds[args.firewallSubnet],
            destinationCidrBlock: "0.0.0.0/0",
            natGatewayId: nat.id,
        }, childOptions(this));
        new aws.ec2.Route("nat-return-via-firewall", {
            routeTableId: args.routeTableIds[args.natPublicSubnet],
            destinationCidrBlock: args.subnetCidrs[args.applicationSubnet],
            vpcEndpointId: endpointId,
        }, childOptions(this));

        this.firewallArn = firewall.arn;
        this.natGatewayId = nat.id;
        this.registerOutputs({firewallArn: firewall.arn, natGatewayId: nat.id});
    }
}
