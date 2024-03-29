local common = import 'common.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.acme_dns;

local base_config = {
  // disable admin interface
  admin: {
    disabled: true,
  },
  apps: {
    http: {
      servers: {
        srv0: {
          listen: [ ':%d' % common.caddy.api_port ],
          routes: [
            {
              // Enable basic auth for /register endpoint
              match: [
                {
                  path: [
                    '/register',
                  ],
                },
              ],
              handle: [
                {
                  handler: 'authentication',
                  providers: {
                    http_basic: {
                      accounts: [
                        {
                          username: params.api.basicAuth.username,
                          // this field is patched by script `render-config`
                          // in the configmap
                          password: 'THE_PASSWORD',
                        },
                      ],
                      hash: { algorithm: 'bcrypt' },
                      realm: 'acme-dns',
                    },
                  },
                },
              ],
            },
            // for the container health check
            {
              match: [
                {
                  path: [
                    '/healthz',
                  ],
                },
              ],
              handle: [
                {
                  body: 'OK',
                  handler: 'static_response',
                  status_code: 200,
                },
              ],
            },
            {
              handle: [
                {
                  handler: 'reverse_proxy',
                  upstreams: [
                    { dial: '127.0.0.1:%d' % common.acme_dns.api_port },
                  ],
                },
              ],
            },
          ],
        },
      },
    },
  },
};

{
  configmap: kube.ConfigMap(common.caddy.cm_name) {
    data: {
      'render-config': |||
        set -e
        pw=`caddy hash-password --plaintext ${BASIC_AUTH_PASSWORD}`
        sed -e "s/THE_PASSWORD/${pw}/" /etc/caddy/caddy.json.tpl > /etc/caddy.out/caddy.json
      |||,
      'caddy.json.tpl': '%s' % [ base_config ],
    },
  },
  pwsecret: kube.Secret(common.caddy.basicauth_secretname) {
    stringData: {
      BASIC_AUTH_PASSWORD: params.api.basicAuth.password,
    },
  },
}
