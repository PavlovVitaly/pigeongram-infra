#!/bin/bash
set -e

BACKUP_FILE="backup-$(date +%Y%m%d-%H%M%S).sql"

echo "▶ Бэкап PostgreSQL..."
kubectl exec -n pigeongram postgres-0 -- pg_dump -U pigeongram pigeongram > "$BACKUP_FILE"

echo "✅ Бэкап сохранён: $BACKUP_FILE"