# shellcheck shell=bash
# modules/75-databases.sh — database clients (G42-45). psql, redis-cli and
# mysql are Ubuntu packages (system part); mongosh is MongoDB's tarball, in
# the home.

databases_setup() {
  log_step "Database clients"
  on MONGOSH && tar_app_install MONGOSH mongosh bin/mongosh
  return 0
}
