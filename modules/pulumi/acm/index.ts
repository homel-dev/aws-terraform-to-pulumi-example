import * as aws from "@pulumi/aws";
import * as pulumi from "@pulumi/pulumi";
import {ComponentArgs, childOptions, componentOptions} from "../common";

export interface AcmArgs extends ComponentArgs {
    domainName: string;
    zoneId: pulumi.Input<string>;
    mode: "managed_dns" | "imported";
    importedCertificateArn?: string;
}

export class AcmComponent extends pulumi.ComponentResource {
    readonly certificateArn: pulumi.Output<string>;

    constructor(name: string, args: AcmArgs, opts?: pulumi.ComponentResourceOptions) {
        super("myorg:tls:Acm", name, {}, componentOptions(opts));
        if (args.mode === "imported") {
            this.certificateArn = pulumi.output(args.importedCertificateArn ?? "");
        } else {
            const cert = new aws.acm.Certificate("application", {
                domainName: args.domainName,
                validationMethod: "DNS",
                tags: args.tags,
            }, childOptions(this));
            const challenge = cert.domainValidationOptions.apply(options => options[0]);
            const record = new aws.route53.Record("application-cert-validation", {
                zoneId: args.zoneId,
                name: challenge.apply(option => option.resourceRecordName),
                type: challenge.apply(option => option.resourceRecordType),
                records: [challenge.apply(option => option.resourceRecordValue)],
                ttl: 60,
                allowOverwrite: true,
            }, childOptions(this));
            const validated = new aws.acm.CertificateValidation("application", {
                certificateArn: cert.arn,
                validationRecordFqdns: [record.fqdn],
            }, childOptions(this));
            this.certificateArn = validated.certificateArn;
        }
        this.registerOutputs({certificateArn: this.certificateArn});
    }
}
