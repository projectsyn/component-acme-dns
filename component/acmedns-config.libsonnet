local common = import 'common.libsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.acme_dns;

local baseConfig = {
  sections: {
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
  },
};

{
  configmap: kube.ConfigMap(common.acme_dns.cm_name) {
    data: {
      'config.cfg': std.manifestIni(
        baseConfig { sections+: com.makeMergeable(params.config) }
      ),
    },
  },
}
