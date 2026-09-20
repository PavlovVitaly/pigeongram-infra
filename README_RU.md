# Pigeongram Infrastructure

[Русская версия](README_RU.md) | [English version](README_EN.md)

## Назначение

`pigeongram-infra` — набор Kubernetes-манифестов и shell-скриптов для инфраструктуры Pigeongram. В текущем составе есть ресурсы для пространства имён приложения, PostgreSQL, Redis, MinIO, самого `pigeongram-chat`, Ingress NGINX и cert-manager, а также скрипты начальной подготовки сервера, развёртывания и резервного копирования PostgreSQL.

Описание составлено по текущим манифестам, скриптам и конфигурационным файлам. Наличие ресурса в репозитории не означает, что он был применён к кластеру или успешно работает.

## Структура проекта

```text
k3s/
  kustomization.yaml       корневой список ресурсов Kustomize
  namespace.yaml           пространство имён pigeongram
  secrets.yaml             Secret с паролями и учётными данными зависимостей
  app.yaml                 Service и Deployment приложения
  postgres.yaml            Service и StatefulSet PostgreSQL
  redis.yaml               Service, Deployment и PVC Redis
  minio.yaml               Service, StatefulSet и Ingress консоли MinIO
  ingress-nginx.yaml       HelmChart и Namespace для ingress-nginx
  cert-manager.yaml        HelmChart, Namespace и ClusterIssuer
  ingress.yaml             Ingress приложения и маршрута MinIO
  nginx-configmap.yaml     конфигурация NGINX reverse proxy
scripts/
  init-server.sh           начальная настройка Linux-сервера и k3s
  deploy.sh                установка ingress-компонентов и применение Kustomize
  backup-db.sh             дамп PostgreSQL через kubectl exec
docker/
  .env.production          набор production-переменных окружения
```

## Состав инфраструктуры

### Пространство имён

`k3s/namespace.yaml` создаёт пространство имён `pigeongram`. В `k3s/kustomization.yaml` оно указано как namespace по умолчанию для перечисленных ресурсов.

### Приложение Pigeongram

`k3s/app.yaml` описывает:

- Service `app` с портом `8080`;
- Deployment `pigeongram` с одной репликой;
- контейнер из образа `ghcr.io/pavlovvitaly/pigeongram-chat:latest`;
- `imagePullSecrets` с именем `ghcr-secret`;
- настройки подключения к PostgreSQL, Redis и MinIO через значения манифеста и ссылки на `pigeongram-secrets`.

Манифест передаёт приложению имена Kubernetes-сервисов `postgres`, `redis` и `minio` как внутренние адреса зависимостей. Для MinIO задаётся bucket `pigeongram-files` и публичный адрес `https://pigeongram.com.ru`.

### PostgreSQL

`k3s/postgres.yaml` создаёт Service `postgres` и StatefulSet с одной репликой PostgreSQL `15-alpine`. Данные подключаются через volume claim template с запросом хранилища `10Gi`. Имя пользователя и базы — `pigeongram`; пароль берётся из `pigeongram-secrets`.

### Redis

`k3s/redis.yaml` создаёт Service и Deployment Redis `7-alpine` с одной репликой. Redis запускается с включённым AOF, обязательным паролем и постоянным томом через PVC `redis-data` размером `5Gi`.

### MinIO

`k3s/minio.yaml` создаёт Service MinIO с портами API `9000` и консоли `9001`, а также StatefulSet с одной репликой образа `minio/minio:latest`. Данные хранятся в volume claim template размером `20Gi`.

В том же файле описан Ingress `minio-console` для хоста `minio.pigeongram.com.ru`, направленный на порт консоли `9001`. Для него указаны TLS-secret и issuer Let's Encrypt.

### Ingress NGINX

`k3s/ingress-nginx.yaml` описывает Namespace `ingress-nginx` и HelmChart ingress-nginx версии `4.9.0`. В конфигурации включён Service типа `NodePort` с портами `30080` и `30443`, размер тела запроса ограничен `100m`, а тайм-ауты прокси заданы в секундах. Метрики контроллера включены.

### cert-manager

`k3s/cert-manager.yaml` описывает Namespace `cert-manager`, HelmChart cert-manager версии `1.14.4` с установкой CRD и `ClusterIssuer` `letsencrypt-prod`. Issuer использует ACME Let's Encrypt и HTTP-01 solver через класс ingress `nginx`.

### Ingress приложения и MinIO API

`k3s/ingress.yaml` содержит два Ingress:

- `pigeongram-app` направляет HTTPS-трафик хоста `pigeongram.com.ru` на Service `app` порт `8080`, задаёт размер тела запроса `100m`, тайм-ауты и настройку WebSocket;
- `pigeongram-minio` направляет путь `/minio/(.*)` того же хоста на Service `minio` порт `9000` и применяет rewrite пути.

Оба Ingress используют TLS-secret `pigeongram-tls` и issuer `letsencrypt-prod`.

### Конфигурация NGINX

`k3s/nginx-configmap.yaml` содержит отдельную конфигурацию NGINX. Она задаёт upstream `app:8080`, проксирует статические ресурсы и обычные HTTP-запросы, а для `/ws` включает HTTP/1.1, Upgrade/Connection headers и тайм-аут чтения WebSocket.

В текущем `k3s/kustomization.yaml` этот ConfigMap перечислен не был, поэтому README фиксирует его наличие в репозитории, но не утверждает, что он применяется текущим Kustomize-набором.

## Секреты и конфигурация

`k3s/secrets.yaml` описывает Secret `pigeongram-secrets` типа `Opaque` со значениями для:

- пароля PostgreSQL;
- пароля Redis;
- root-пользователя MinIO;
- root-пароля MinIO.

Файл содержит строковые значения-заглушки или конфигурационные значения, поэтому перед использованием его содержимое должно рассматриваться как чувствительная конфигурация. README намеренно не дублирует секреты.

Deployment приложения получает чувствительные значения через `secretKeyRef`. Открытые имена ключей должны совпадать между `secrets.yaml` и `app.yaml`.

`docker/.env.production` содержит набор переменных для production-среды: сервер, домен, сессии, PostgreSQL, Redis, MinIO, SMTP, Telegram и GitHub. Эти переменные не следует считать автоматически используемыми Kubernetes-манифестами: непосредственные ссылки на этот файл в манифестах не обнаружены.

В `.gitignore` инфраструктурного проекта указаны `k3s/secrets.yaml` и файлы `*.env`, но наличие файла в рабочем каталоге само по себе не доказывает, что конкретные секреты не попадали в историю Git. Секретные значения в документацию и команды не включаются.

## Скрипты

### `scripts/deploy.sh`

Скрипт:

1. применяет манифесты ingress-nginx и cert-manager;
2. ожидает готовности выбранных Pod'ов;
3. применяет каталог `k3s` через Kustomize;
4. выводит список Pod'ов и Ingress в пространстве имён `pigeongram`.

Это описание поведения скрипта, а не инструкция по его запуску.

### `scripts/init-server.sh`

Скрипт рассчитан на начальную настройку Linux-сервера от имени root. По функциям внутри файла он:

- обновляет систему и устанавливает базовые пакеты;
- устанавливает k3s без Traefik;
- настраивает kubeconfig и алиасы `kubectl`;
- устанавливает Helm;
- устанавливает Portainer через Helm;
- создаёт пользователя `app` и SSH-ключ;
- настраивает UFW, fail2ban и автоматические обновления;
- создаёт swap размером `2G`;
- создаёт каталоги `/opt/pigeongram-chat`, `/opt/pigeongram-infra` и `/backups`;
- при необходимости устанавливает Go версии `1.26.1`;
- выводит версии установленных компонентов и итоговую информацию.

Скрипт выполняет административные и сетевые изменения на сервере. Их параметры и побочные эффекты требуют отдельной проверки перед применением.

### `scripts/backup-db.sh`

Скрипт формирует имя файла с текущими датой и временем, выполняет `pg_dump` в Pod `postgres-0` пространства имён `pigeongram` и сохраняет SQL-вывод в локальный файл резервной копии.

## Связь с `pigeongram-chat`

Инфраструктурные манифесты передают приложению внутренние адреса PostgreSQL, Redis и MinIO, а также значения конфигурации, ожидаемые кодом `pigeongram-chat`. Service `app` предоставляет приложению порт `8080`; Ingress направляет внешний трафик к этому Service.

Из файлов проекта подтверждается следующая связка:

```text
Ingress pigeongram.com.ru
  → Service app:8080
  → контейнер pigeongram-chat
  → Service postgres / redis / minio
```

Для файловых запросов отдельный Ingress направляет путь `/minio/` к MinIO API. Конкретное соответствие всех внешних URL и настроек приложения определяется одновременно манифестами и кодом `pigeongram-chat`.

## Порядок ресурсов в Kustomize

`k3s/kustomization.yaml` перечисляет ресурсы в следующем порядке:

1. `namespace.yaml`;
2. `secrets.yaml`;
3. `postgres.yaml`;
4. `redis.yaml`;
5. `minio.yaml`;
6. `app.yaml`;
7. `ingress-nginx.yaml`;
8. `cert-manager.yaml`;
9. `ingress.yaml`.

Этот список отражает декларативный состав Kustomize. Он не является гарантией фактического порядка готовности всех Kubernetes-ресурсов.

## Ограничения и границы текущих файлов

- В проекте присутствуют значения `latest` для образа MinIO и приложения; фиксированная версия для них в соответствующих манифестах не задана.
- В `app.yaml` указана одна реплика приложения, PostgreSQL и MinIO; Redis также описан одной репликой.
- `k3s/secrets.yaml` содержит чувствительные поля и значения-заглушки; способ безопасной подстановки production-секретов отдельным механизмом в этих файлах не описан.
- `k3s/nginx-configmap.yaml` присутствует в каталоге, но не указан в списке `resources` Kustomize.
- `docker/.env.production` содержит больше переменных, чем явно используется манифестами; по одному наличию файла нельзя заключить, что SMTP, Telegram, JWT или GitHub-настройки используются текущим приложением.
- Скрипты предполагают наличие инструментов и ресурсов, включая `kubectl`, доступ к кластеру, Helm, права root и Pod `postgres-0`; эти предположения не являются проверкой окружения.
- В манифестах заявлены TLS, домены и Let's Encrypt, но успешная выдача сертификатов, DNS и доступность внешнего кластера этим репозиторием не подтверждаются.
- Резервная копия сохраняется в текущий локальный каталог; отдельная политика хранения, шифрования или удаления копий в скрипте не задана.

## Развёртывание

TODO: добавить инструкции по подготовке окружения, применению манифестов и проверке состояния инфраструктуры.
