# Symfony Docker

Running up a basic development environment with Symfony and MariaDB in Docker Compose

## Usage

```bash
docker compose build
docker compose up
```

You can also connect directly to the PHP app in order to run `composer` or `bin/console` commands:

```bash
docker compose exec app bash
```