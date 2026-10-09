import * as aws from "@pulumi/aws";
import * as pulumi from "@pulumi/pulumi";
import {ComponentArgs, childOptions, componentOptions} from "../common";

export interface GuardDutyArgs extends ComponentArgs {
    enabled: boolean;
}

export class GuardDutyComponent extends pulumi.ComponentResource {
    readonly detectorId: pulumi.Output<string> | undefined;

    constructor(name: string, args: GuardDutyArgs, opts?: pulumi.ComponentResourceOptions) {
        super("myorg:security:GuardDuty", name, {}, componentOptions(opts));
        if (args.enabled) {
            const detector = new aws.guardduty.Detector("regional", {
                enable: true,
                findingPublishingFrequency: "FIFTEEN_MINUTES",
                tags: args.tags,
            }, childOptions(this));
            this.detectorId = detector.id;
        }
        this.registerOutputs({detectorId: this.detectorId});
    }
}
