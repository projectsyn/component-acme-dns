{
  acme_dns: {
    api_port: 8000,
    cm_name: 'acmedns-config',
    datadir: '/var/lib/acme-dns',
    dns_port: 5533,
  },
  caddy: {
    cm_name: 'acmedns-caddy-config',
    basicauth_secretname: 'acmedns-basicauth',
    api_port: 8080,
  },
  image(imgspec): '%(registry)s/%(repository)s:%(tag)s' % imgspec,
}
