local k8up = import 'lib/backup-k8up.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local common = import 'common.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.acme_dns;
local backup_params = params.persistence.backup;

local backupPass =
  kube.Secret('acme-dns-backup-password') {
    stringData: {
      password: backup_params.password,
    },
  };

local bucketCredentials =
  kube.Secret('acme-dns-backup-s3-credentials') {
    stringData: {
      accesskey: backup_params.accesskey,
      secretkey: backup_params.secretkey,
    },
  };

local schedule =
  k8up.Schedule(
    'acme-dns',
    backup_params.schedule,
    backupkey={
      name: backupPass.metadata.name,
      key: 'password',
    },
    bucket=backup_params.bucket,
    s3secret={
      name: bucketCredentials.metadata.name,
      accesskeyname: 'accesskey',
      secretkeyname: 'secretkey',
    },
    create_bucket=false,
  ) {
    spec+: {
      backend+: {
        s3+: {
          [if backup_params.endpoint != null then 'endpoint']: backup_params.endpoint,
        },
      },
    },
  };

local prebackuppod(volspec) =
  k8up.PreBackupPod(
    'acme-dns-backup',
    common.image(params.images.sqlite),
    '/bin/sh -c "sqlite3 %s .dump | gzip -f"' % common.acme_dns.dbpath,
    fileext='.sql.gz'
  ) {
    spec+: {
      pod+: {
        spec+: {
          affinity: {
            podAffinity: {
              requiredDuringSchedulingIgnoredDuringExecution: [
                {
                  labelSelector: {
                    matchExpressions: [ {
                      key: 'name',
                      operator: 'In',
                      values: [ 'acme-dns' ],
                    } ],
                  },
                  topologyKey: 'kubernetes.io/hostname',
                },
              ],
            },
          },
          containers: [
            super.containers[0] {
              volumeMounts_: {
                acmedns_data: {
                  mountPath: common.acme_dns.datadir,
                },
              },
            },
          ],
          volumes_: {
            acmedns_data: volspec,
          },
        },
      },
    },
  };


{
  secrets: [
    backupPass,
    bucketCredentials,
  ],
  schedule: schedule.schedule,
  prebackuppod: prebackuppod,
}
