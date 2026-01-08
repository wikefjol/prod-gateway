## Where to look cheat sheet:

For DEV debugging, run these in three terminals:

**Terminal A (Apache edge + proxy)**

```bash
sudo tail -F /var/log/apache2/lamassu-https-access.log /var/log/apache2/lamassu-proxy.log /var/log/apache2/lamassu-https-error.log
```

**Terminal B (APISIX)**

```bash
docker exec -it apisix-dev-apisix-1 sh -lc 'tail -F /usr/local/apisix/logs/access.log /usr/local/apisix/logs/error.log'
```

**Terminal C (portal-backend)**

```bash
docker compose --project-name apisix-dev -f docker-compose.yml -f docker-compose.dev.yml --env-file .env.dev logs --timestamps -f portal-backend
```
...

