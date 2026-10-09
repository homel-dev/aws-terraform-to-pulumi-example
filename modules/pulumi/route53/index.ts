import * as aws from "@pulumi/aws";
import * as pulumi from "@pulumi/pulumi";
import {ComponentArgs, childOptions, componentOptions} from "../common";

export interface Route53Args extends ComponentArgs {
    zoneName: string;
}

export class Route53Component extends pulumi.ComponentResource {
    readonly zoneId: pulumi.Output<string>;

    constructor(name: string, args: Route53Args, opts?: pulumi.ComponentResourceOptions) {
        super("myorg:dns:Route53", name, {}, componentOptions(opts));
        const zone = new aws.route53.Zone("public", {
            name: args.zoneName,
            comment: "MyOrg POC public application DNS zone",
            forceDestroy: false,
            tags: args.tags,
        }, childOptions(this));
        this.zoneId = zone.zoneId;
        this.registerOutputs({zoneId: this.zoneId});
    }

    addApplicationAlias(args: {
        domain: string;
        albDnsName: pulumi.Input<string>;
        albZoneId: pulumi.Input<string>;
    }): void {
        new aws.route53.Record("application-alias", {
            zoneId: this.zoneId,
            name: args.domain,
            type: "A",
            aliases: [{
                name: args.albDnsName,
                zoneId: args.albZoneId,
                evaluateTargetHealth: false,
            }],
        }, childOptions(this));
    }
}
