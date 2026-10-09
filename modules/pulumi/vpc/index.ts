import * as aws from "@pulumi/aws";
import * as pulumi from "@pulumi/pulumi";
import {ComponentArgs, childOptions, componentOptions} from "../common";

export interface SubnetSpec {
    type: "public" | "application" | "database" | "firewall";
    availability_zone: string;
    cidr: string;
}

export interface VpcArgs extends ComponentArgs {
    cidr: string;
    subnets: Record<string, SubnetSpec>;
}

export class VpcComponent extends pulumi.ComponentResource {
    readonly vpcId: pulumi.Output<string>;
    readonly internetGateway: aws.ec2.InternetGateway;
    readonly subnetIds: Record<string, pulumi.Output<string>> = {};
    readonly subnetCidrs: Record<string, string> = {};
    readonly routeTableIds: Record<string, pulumi.Output<string>> = {};

    constructor(name: string, args: VpcArgs, opts?: pulumi.ComponentResourceOptions) {
        super("myorg:network:Vpc", name, {}, componentOptions(opts));
        const vpc = new aws.ec2.Vpc("vpc", {
            cidrBlock: args.cidr,
            enableDnsSupport: true,
            enableDnsHostnames: true,
            tags: {...args.tags, Name: args.namePrefix},
        }, childOptions(this));
        this.vpcId = vpc.id;
        const igw = new aws.ec2.InternetGateway("internet-gateway", {
            vpcId: vpc.id,
            tags: args.tags,
        }, childOptions(this));
        this.internetGateway = igw;

        for (const [key, spec] of Object.entries(args.subnets)) {
            const subnet = new aws.ec2.Subnet(`subnet-${key}`, {
                vpcId: vpc.id,
                cidrBlock: spec.cidr,
                availabilityZone: spec.availability_zone,
                mapPublicIpOnLaunch: false,
                tags: {...args.tags, Name: `${args.namePrefix}-${key}`, SubnetRole: spec.type},
            }, childOptions(this));
            const routeTable = new aws.ec2.RouteTable(`route-table-${key}`, {
                vpcId: vpc.id,
                tags: {...args.tags, Name: `${args.namePrefix}-${key}`},
            }, childOptions(this));
            new aws.ec2.RouteTableAssociation(`route-association-${key}`, {
                subnetId: subnet.id,
                routeTableId: routeTable.id,
            }, childOptions(this));
            if (spec.type === "public") {
                new aws.ec2.Route(`public-default-${key}`, {
                    routeTableId: routeTable.id,
                    destinationCidrBlock: "0.0.0.0/0",
                    gatewayId: igw.id,
                }, childOptions(this));
            }
            this.subnetIds[key] = subnet.id;
            this.subnetCidrs[key] = spec.cidr;
            this.routeTableIds[key] = routeTable.id;
        }
        this.registerOutputs({vpcId: this.vpcId, subnetIds: this.subnetIds, routeTableIds: this.routeTableIds});
    }
}
