# Pigeongram Infrastructure

[Русская версия](README_RU.md) | [English version](README_EN.md)

## Purpose

`pigeongram-infra` is a collection of Kubernetes manifests and shell scripts for Pigeongram infrastructure. The current repository contains resources for the application namespace, PostgreSQL, Redis, MinIO, the `pigeongram-chat` application, NGINX Ingress, and cert-manager. It also contains scripts for initial server preparation, deployment, and PostgreSQL backups.

This document is based on the current manifests, scripts, and configuration files. The presence of a resource in the repository does not mean that it has been applied to a cluster or is currently working.

## Project structure

```text
k3s/
  kustomization.yaml       root list of Kustomize resources
  namespace.yaml           pigeongram namespace
  secrets.yaml             Secret with dependency passwords and credentials
  app.yaml                 application Service and Deployment
  postgres.yaml            PostgreSQL Service and StatefulSet
  redis.yaml               Redis Service, Deployment, and PVC
  minio.yaml               MinIO Service, StatefulSet, and console Ingress
  ingress-nginx.yaml       ingress-nginx HelmChart and Namespace
  cert-manager.yaml        cert-manager HelmChart, Namespace, and ClusterIssuer
  ingress.yaml             application and MinIO route Ingress resources
  nginx-configmap.yaml     NGINX reverse-proxy configuration
scripts/
  init-server.sh           initial Linux server and k3s setup
  deploy.sh                ingress component installation and Kustomize application
  backup-db.sh             PostgreSQL dump through kubectl exec
docker/
  .env.production          set of production environment variables
```

## Infrastructure components

### Namespace

`k3s/namespace.yaml` creates the `pigeongram` namespace. `k3s/kustomization.yaml` sets it as the default namespace for the listed resources.

### Pigeongram application

`k3s/app.yaml` defines:

- the `app` Service on port `8080`;
- the `pigeongram` Deployment with one replica;
- a container using `ghcr.io/pavlovvitaly/pigeongram-chat:latest`;
- an `imagePullSecrets` reference named `ghcr-secret`;
- PostgreSQL, Redis, and MinIO connection settings supplied as manifest values and references to `pigeongram-secrets`.

The manifest passes the Kubernetes service names `postgres`, `redis`, and `minio` to the application as internal dependency addresses. It sets the `pigeongram-files` bucket and the public MinIO address `https://pigeongram.com.ru`.

### PostgreSQL

`k3s/postgres.yaml` creates the `postgres` Service and a one-replica PostgreSQL `15-alpine` StatefulSet. Data is mounted through a volume claim template requesting `10Gi` of storage. The username and database are both `pigeongram`; the password comes from `pigeongram-secrets`.

### Redis

`k3s/redis.yaml` creates a Redis Service and a one-replica `7-alpine` Deployment. Redis starts with AOF enabled, a required password, and persistent storage through the `redis-data` PVC requesting `5Gi`.

### MinIO

`k3s/minio.yaml` creates a MinIO Service with API port `9000` and console port `9001`, and a one-replica StatefulSet using `minio/minio:latest`. Data is stored through a `20Gi` volume claim template.

The same file defines the `minio-console` Ingress for `minio.pigeongram.com.ru`, pointing to console port `9001`. It specifies a TLS secret and a Let's Encrypt issuer.

### NGINX Ingress

`k3s/ingress-nginx.yaml` defines the `ingress-nginx` Namespace and an ingress-nginx HelmChart version `4.9.0`. The configuration enables a `NodePort` Service with ports `30080` and `30443`, limits request bodies to `100m`, sets proxy timeouts in seconds, and enables controller metrics.

### cert-manager

`k3s/cert-manager.yaml` defines the `cert-manager` Namespace, a cert-manager HelmChart version `1.14.4` with CRD installation enabled, and the `letsencrypt-prod` `ClusterIssuer`. The issuer uses Let's Encrypt ACME and an HTTP-01 solver through the `nginx` ingress class.

### Application and MinIO API Ingress

`k3s/ingress.yaml` contains two Ingress resources:

- `pigeongram-app` routes HTTPS traffic for `pigeongram.com.ru` to the `app` Service on port `8080`, sets the request-body limit and timeouts, and enables WebSocket-related configuration;
- `pigeongram-minio` routes `/minio/(.*)` on the same host to the `minio` Service on port `9000` and applies a path rewrite.

Both Ingress resources use the `pigeongram-tls` TLS secret and the `letsencrypt-prod` issuer.

### NGINX configuration

`k3s/nginx-configmap.yaml` contains a separate NGINX configuration. It defines the `app:8080` upstream, proxies static resources and ordinary HTTP requests, and configures HTTP/1.1, Upgrade/Connection headers, and a WebSocket read timeout for `/ws`.

This ConfigMap is not listed in the `resources` section of the current `k3s/kustomization.yaml`. Therefore, this README records its presence in the repository but does not claim that the current Kustomize set applies it.

## Secrets and configuration

`k3s/secrets.yaml` defines the `pigeongram-secrets` `Opaque` Secret with values for:

- the PostgreSQL password;
- the Redis password;
- the MinIO root user;
- the MinIO root password.

The file contains placeholder or configuration values, so its contents must be treated as sensitive configuration before use. This README intentionally does not reproduce the secret values.

The application Deployment obtains sensitive values through `secretKeyRef`. The key names must match between `secrets.yaml` and `app.yaml`.

`docker/.env.production` contains production variables for the server, domain, session, PostgreSQL, Redis, MinIO, SMTP, Telegram, and GitHub. These variables must not be assumed to be automatically used by the Kubernetes manifests: no direct reference to this file was found in the manifests.

The infrastructure project's `.gitignore` lists `k3s/secrets.yaml` and `*.env`, but the presence of a file in the working directory alone does not prove that particular secrets have never entered Git history. Secret values are not included in this documentation or in commands.

## Scripts

### `scripts/deploy.sh`

The script:

1. applies the ingress-nginx and cert-manager manifests;
2. waits for selected Pods to become ready;
3. applies the `k3s` directory through Kustomize;
4. prints Pods and Ingress resources in the `pigeongram` namespace.

This is a description of the script's behavior, not instructions for running it.

### `scripts/init-server.sh`

The script is intended to initialize a Linux server as root. Based on its functions, it:

- updates the system and installs base packages;
- installs k3s without Traefik;
- configures kubeconfig and `kubectl` aliases;
- installs Helm;
- installs Portainer through Helm;
- creates the `app` user and an SSH key;
- configures UFW, fail2ban, and automatic updates;
- creates a `2G` swap file;
- creates `/opt/pigeongram-chat`, `/opt/pigeongram-infra`, and `/backups`;
- installs Go `1.26.1` when needed;
- prints versions of installed components and final information.

The script performs administrative and network changes on the server. Its parameters and side effects require a separate review before it is applied.

### `scripts/backup-db.sh`

The script builds a filename containing the current date and time, runs `pg_dump` in the `postgres-0` Pod in the `pigeongram` namespace, and saves the SQL output to a local backup file.

## Relationship with `pigeongram-chat`

The infrastructure manifests pass internal PostgreSQL, Redis, and MinIO addresses to the application, together with configuration values expected by `pigeongram-chat`. The `app` Service exposes application port `8080`; the Ingress routes external traffic to this Service.

The following connection is confirmed by the project files:

```text
Ingress pigeongram.com.ru
  → Service app:8080
  → pigeongram-chat container
  → Service postgres / redis / minio
```

For file requests, a separate Ingress routes `/minio/` to the MinIO API. The exact correspondence between all external URLs and application settings is determined jointly by these manifests and the `pigeongram-chat` source code.

## Kustomize resource list

`k3s/kustomization.yaml` lists resources in this order:

1. `namespace.yaml`;
2. `secrets.yaml`;
3. `postgres.yaml`;
4. `redis.yaml`;
5. `minio.yaml`;
6. `app.yaml`;
7. `ingress-nginx.yaml`;
8. `cert-manager.yaml`;
9. `ingress.yaml`.

This list describes the declarative Kustomize composition. It is not a guarantee of the actual readiness order of all Kubernetes resources.

## Limitations and boundaries of the current files

- The repository uses `latest` for the MinIO and application images; the corresponding manifests do not pin their versions.
- `app.yaml` declares one application replica; PostgreSQL and MinIO are also declared with one replica, and Redis is declared as a one-replica Deployment.
- `k3s/secrets.yaml` contains sensitive fields and placeholder values; these files do not describe a separate mechanism for safely injecting production secrets.
- `k3s/nginx-configmap.yaml` exists in the directory but is not included in the Kustomize `resources` list.
- `docker/.env.production` contains more variables than the manifests explicitly use; its presence alone does not prove that SMTP, Telegram, JWT, or GitHub settings are used by the current application.
- The scripts assume tools and resources such as `kubectl`, cluster access, Helm, root privileges, and a `postgres-0` Pod; those assumptions are not environment checks.
- The manifests declare TLS, domains, and Let's Encrypt, but successful certificate issuance, DNS configuration, and external cluster availability are not confirmed by this repository.
- The backup is saved in the current local directory; the script does not define a retention, encryption, or deletion policy for backups.

## Deployment

TODO: Add instructions for environment preparation, applying manifests, and checking infrastructure status.
