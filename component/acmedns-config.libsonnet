local common = import 'common.libsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.acme_dns;

local baseConfig = {
  general: {
    listen: '0.0.0.0:%d' % common.acme_dns.dns_port,
    protocol: 'both4',
    debug: false,
  },
  database: {
    engine: 'sqlite3',
    connection: '%s/acme-dns.db' % common.acme_dns.datadir,
  },
  api: {
    ip: '127.0.0.1',
    disable_registration: false,
    port: common.acme_dns.api_port,
    tls: 'none',
    corsorigins: [ '*' ],
    use_header: true,
    header_name: 'X-Forwarded-For',
  },
};

local manifestToml(cfg) =
  local manifestSection(k, v) =
    local header = '[%s]' % k;
    local renderValue(v) =
      if std.isArray(v) then
        '%s' % [ v ]
      else if std.isObject(v) then
        error 'Cannot render objects in TOML config'
      else if std.isString(v) || std.isNumber(v) then
        '"%s"' % v
      else
        '%s' % v;
    local rendered(v) = [
      '%s=%s' % [ k, renderValue(v[k]) ]
      for k in std.objectFields(v)
    ];
    std.join('\n', [ header ] + rendered(v));

  std.join('\n', [ manifestSection(k, cfg[k]) for k in std.objectFields(cfg) ]);

{
  configmap: kube.ConfigMap(common.acme_dns.cm_name) {
    data: {
      'config.cfg': manifestToml(
        baseConfig + com.makeMergeable(params.config)
      ),
    },
  },
}
