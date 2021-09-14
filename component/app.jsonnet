local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.acme_dns;
local argocd = import 'lib/argocd.libjsonnet';

local app = argocd.App('acme-dns', params.namespace);

{
  'acme-dns': app,
}
