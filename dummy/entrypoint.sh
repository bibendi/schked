#!/bin/sh
set -e

bundle config set without "development test"
bundle check || bundle install --quiet

exec "$@"