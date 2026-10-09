locals {
  config_base_dir = "${path.root}/config"

  zone_dirs = [
    for d in fileset(local.config_base_dir, "**/zone.yml") :
    dirname(d)
  ]

  zones_raw = {
    for dir in local.zone_dirs :
    trimsuffix(basename(dir), "/") => yamldecode(file("${local.config_base_dir}/${dir}/zone.yml")).zone
  }

  records_raw = flatten([
    for dir in local.zone_dirs : [
      for filename in fileset("${local.config_base_dir}/${dir}/records", "*.yml") : {
        zone = trimsuffix(basename(dir), "/")
        record = merge(
          { ttl = local.defaults.ttl },
          yamldecode(file("${local.config_base_dir}/${dir}/records/${filename}")).record
        )
      }
    ]
  ])

  records_grouped = {
    for r in local.records_raw :
    "${r.zone}/${r.record.name}/${upper(r.record.type)}" => merge(r.record, { zone = r.zone })
  }

  zones = {
    for zone_name, zone_config in local.zones_raw :
    zone_name => merge(zone_config, { name = zone_name })
  }

  records = local.records_grouped
}
