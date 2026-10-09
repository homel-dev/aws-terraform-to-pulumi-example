import * as pulumi from "@pulumi/pulumi";

export type Tags = Record<string, string>;

export interface ComponentArgs {
    namePrefix: string;
    tags: Tags;
}

export function childOptions(parent: pulumi.ComponentResource): pulumi.CustomResourceOptions {
    return {parent};
}

export function componentOptions(opts?: pulumi.ComponentResourceOptions): pulumi.ComponentResourceOptions {
    return opts ?? {};
}
