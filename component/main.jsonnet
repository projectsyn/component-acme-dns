local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local common = import 'common.libsonnet';

local acmedns_config = import 'acmedns-config.libsonnet';
local backup = import 'backup.libsonnet';
local caddy_config = import 'caddy-config.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.acme_dns;
local on_ocp3 = inv.parameters.facts.distribution == 'openshift3';


local namespace = kube.Namespace(params.namespace);

local pvc = kube.PersistentVolumeClaim('acmedns-data') {
  spec: std.prune({
    storageClassName: params.persistence.storageClassName,
    accessModes: [ 'ReadWriteOnce' ],
    resources: {
      requests: {
        storage: params.persistence.volumeSize,
      },
    },
  }),
};

local dataVolume =
  if params.persistence.enabled then {
    persistentVolumeClaim: {
      claimName: pvc.metadata.name,
    },
  } else {
    emptyDir: {},
  };

local configs = [
  acmedns_config.configmap,
  caddy_config.configmap,
  caddy_config.pwsecret,
];
local confighash =
  local data(c) =
    if c.kind == 'ConfigMap' then
      c.data
    else if c.kind == 'Secret' then
      c.stringData
    else
      error "Unknown config source with kind '%s'" % c.kind;
  std.md5(std.join('\n', [ '%s' % std.manifestJson(data(c)) for c in configs ]));

local deployment = kube.Deployment('acme-dns') {
  spec+: {
    template+: {
      metadata+: {
        annotations+: {
          'acme-dns.syn.tools/config-hash': confighash,
        },
      },
      spec+: {
        default_container:: 'acme_dns',
        containers_:: {
          acme_dns: kube.Container('acme-dns') {
            image: common.image(params.images['acme-dns']),
            ports_: {
              dns: {
                protocol: 'UDP',
                containerPort: common.acme_dns.dns_port,
              },
            },
            volumeMounts_: {
              acmedns_config: {
                mountPath: '/etc/acme-dns',
                readOnly: true,
              },
              acmedns_data: {
                mountPath: common.acme_dns.datadir,
              },
            },
            livenessProbe: {
              failureThreshold: 3,
              httpGet: {
                path: '/health',
                port: common.acme_dns.api_port,
              },
              initialDelaySeconds: 1,
              periodSeconds: 10,
              successThreshold: 1,
              timeoutSeconds: 1,
            },
            readinessProbe: {
              failureThreshold: 3,
              httpGet: {
                path: '/health',
                port: common.acme_dns.api_port,
              },
              initialDelaySeconds: 1,
              periodSeconds: 10,
              successThreshold: 1,
              timeoutSeconds: 1,
            },
          },
          caddy: kube.Container('caddy') {
            image: common.image(params.images.caddy),
            command: [ 'caddy', 'run', '-config', '/etc/caddy/caddy.json' ],
            ports_: {
              api: {
                protocol: 'TCP',
                containerPort: common.caddy.api_port,
              },
            },
            livenessProbe: {
              failureThreshold: 3,
              httpGet: {
                path: '/healthz',
                port: common.caddy.api_port,
              },
              initialDelaySeconds: 1,
              periodSeconds: 10,
              successThreshold: 1,
              timeoutSeconds: 1,
            },
            readinessProbe: {
              failureThreshold: 3,
              httpGet: {
                path: '/healthz',
                port: common.caddy.api_port,
              },
              initialDelaySeconds: 1,
              periodSeconds: 10,
              successThreshold: 1,
              timeoutSeconds: 1,
            },
            volumeMounts_: {
              caddy_config: {
                mountPath: '/etc/caddy',
                readOnly: true,
              },
            },
          },
        },
        initContainers_:: {
          render_caddy_config: kube.Container('render-caddy-config') {
            image: common.image(params.images.caddy),
            command: [ '/bin/sh', '/etc/caddy/render-config' ],
            env_: {
              BASIC_AUTH_PASSWORD: {
                secretKeyRef: {
                  name: common.caddy.basicauth_secretname,
                  key: 'password',
                },
              },
            },
            volumeMounts_: {
              caddy_config: {
                mountPath: '/etc/caddy.out',
              },
              caddy_config_template: {
                mountPath: '/etc/caddy',
              },
            },
          },
        },
        volumes_: {
          acmedns_config: {
            configMap: {
              // mode 0400
              defaultMode: 256,
              name: common.acme_dns.cm_name,
            },
          },
          acmedns_data: dataVolume,
          caddy_config: {
            emptyDir: {},
          },
          caddy_config_template: {
            configMap: {
              name: common.caddy.cm_name,
              items: [
                {
                  key: 'render-config',
                  path: 'render-config',
                  // mode 0700
                  mode: 448,
                },
                {
                  key: 'caddy.json.tpl',
                  path: 'caddy.json.tpl',
                  // mode 0400
                  mode: 256,
                },
              ],
            },
          },
        },
      },
    },
  },
};

local dns_service = kube.Service('acme-dns') {
  target_pod:: deployment.spec.template,
  spec+: {
    ports: [
      {
        name: 'dns',
        port: 53,
        targetPort: common.acme_dns.dns_port,
        protocol: 'UDP',
      },
    ],
    type: 'LoadBalancer',
  },
};

local api_service = kube.Service('acme-dns-api') {
  target_pod:: deployment.spec.template,
  spec+: {
    ports: [
      {
        port: common.caddy.api_port,
        name: 'api',
        targetPort: common.caddy.api_port,
      },
    ],
  },
};

local ingress = (
  if on_ocp3 then
    kube._Object('route.openshift.io/v1', 'Route', 'acme-dns-api') {
      metadata+: {
        annotations+: {
          'kubernetes.io/tls-acme': 'true',
        },
      },
      spec: {
        host: params.api.hostname,
        to: {
          kind: 'Service',
          name: api_service.metadata.name,
        },
        tls: {
          termination: 'edge',
          insecureEdgeTerminationPolicy: 'Redirect',
        },
      },
    }
  else
    kube.Ingress('acme-dns-api') {
      metadata+: {
        annotations+: {
          'cert-manager.io/cluster-issuer': params.api.tls.issuer.name,
        },
      },
      spec: {
        rules: [
          {
            host: params.api.hostname,
            http: {
              paths: [
                {
                  path: '/',
                  pathType: 'Prefix',
                  backend: api_service.name_port,
                },
              ],
            },
          },
        ],
        tls: [
          {
            hosts: [ params.api.hostname ],
            secretName: 'acme-dns-api-cert',
          },
        ],
      },
    }
);

local makeNamespaced(key, obj) =
  if std.isObject(obj) then (
    if std.objectHas(obj, 'kind') then
      com.namespaced(params.namespace, obj)
    else
      obj
  ) else if std.isArray(obj) then (
    std.map(
      function(it)
        if std.objectHas(it, 'kind') then
          com.namespaced(params.namespace, it)
        else
          it,
      obj
    )
  ) else error 'Emitting value which is neither object nor array';

local backup_objs =
  backup.secrets +
  [
    backup.prebackuppod(dataVolume),
    backup.schedule,
  ];

local configure_backup =
  params.persistence.enabled &&
  params.persistence.backup.enabled;

{
  '00_namespace': namespace,
} +
std.mapWithKey(
  makeNamespaced,
  {
    [if params.persistence.enabled then '10_pvc']:
      pvc,
    '10_config': configs,
    '20_deployment': deployment,
    '30_service': [ api_service, dns_service ],
    '40_ingress': ingress,
    [if configure_backup then '50_backup']:
      backup_objs,
  }
)
