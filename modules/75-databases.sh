# shellcheck shell=bash
# modules/75-databases.sh — database clients (G42-45). Servers belong in
# containers (docker run postgres/mongo/redis/mysql), not on the workstation.

databases_setup() {
  log_step "Database clients"
  local pkgs=()
  on PSQL && pkgs+=(postgresql-client)
  on REDIS_CLI && pkgs+=(redis-tools)
  on MYSQL_CLIENT && pkgs+=(mysql-client)
  (( ${#pkgs[@]} )) && apt_install "${pkgs[@]}"
  on MONGOSH && deb_install MONGOSH mongodb-mongosh
  return 0
}
