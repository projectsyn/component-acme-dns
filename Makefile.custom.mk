.PHONY: lint_validate_caddy_config
lint_validate_caddy_config: ## Validate generated Caddy config
	$(eval CADDY_IMAGE := $(shell yq '.parameters.acme_dns.images.caddy|"\(.registry)/\(.repository):\(.tag)"' class/defaults.yml))
	$(eval CADDY_CONFIG := $(shell yq 'select(.metadata.name=="acmedns-caddy-config")|.data."caddy.json.tpl"' tests/golden/defaults/acme-dns/acme-dns/acme-dns/10_config.yaml))
	$(DOCKER_CMD) $(DOCKER_ARGS) $(root_volume) -e CADDY_CONFIG='$(CADDY_CONFIG)' $(CADDY_IMAGE) sh -c 'echo $${CADDY_CONFIG} | sed -e "s#THE_PASSWORD#$$(caddy hash-password --plaintext test)#" | caddy validate --config -'
