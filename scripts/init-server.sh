#!/bin/bash
# =====================================================
# PigeonGram - Начальная инициализация сервера
# =====================================================

set -e

# Цвета для вывода
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}   $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
}

print_step() {
    echo -e "\n${GREEN}▶ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ️ $1${NC}"
}

# Проверка root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Этот скрипт должен запускаться от root (sudo)"
        exit 1
    fi
}

# =====================================================
# 1. Обновление системы
# =====================================================
update_system() {
    print_step "Обновление системы"
    apt update && apt upgrade -y && apt autoremove -y
    print_success "Система обновлена"
}

# =====================================================
# 2. Установка базовых пакетов
# =====================================================
install_base_packages() {
    print_step "Установка базовых пакетов"
    
    apt install -y \
        curl wget git vim htop net-tools \
        ufw fail2ban unattended-upgrades \
        jq ncdu tree zip unzip mc rsync tmux \
        build-essential software-properties-common \
        apt-transport-https ca-certificates gnupg lsb-release \
        iotop iftop openssl
    
    print_success "Базовые пакеты установлены"
}

# =====================================================
# 3. Установка k3s (вместо Docker отдельно)
# =====================================================
install_k3s() {
    print_step "Установка k3s"
    
    if command -v k3s &> /dev/null; then
        print_info "k3s уже установлен"
        k3s --version
        return 0
    fi
    
    curl -sfL https://get.k3s.io | sh -s - \
        --write-kubeconfig-mode 644 \
        --disable traefik
    
    # Ждём запуска
    sleep 10
    systemctl is-active --quiet k3s
    
    # Копируем kubeconfig для удобства
    mkdir -p /home/app/.kube
    cp /etc/rancher/k3s/k3s.yaml /home/app/.kube/config
    chown -R app:app /home/app/.kube
    
    # Добавляем kubectl alias
    echo 'alias k="kubectl"' >> /home/app/.bashrc
    
    print_success "k3s установлен"
}

# =====================================================
# 4. Установка Helm
# =====================================================
install_helm() {
    print_step "Установка Helm"
    
    if command -v helm &> /dev/null; then
        print_info "Helm уже установлен"
        helm version
        return 0
    fi
    
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    
    print_success "Helm установлен"
}

# =====================================================
# 5. Установка Portainer
# =====================================================
install_portainer() {
    print_step "Установка Portainer"
    
    # Проверяем, не установлен ли уже
    if kubectl get namespace portainer &> /dev/null; then
        print_info "Portainer уже установлен"
        return 0
    fi
    
    # Устанавливаем Portainer через Helm
    helm repo add portainer https://portainer.github.io/k8s/
    helm repo update
    helm upgrade --install portainer portainer/portainer \
        --namespace portainer \
        --create-namespace \
        --set service.type=NodePort \
        --set service.nodePort=30777 \
        --set ingress.enabled=false
    
    print_success "Portainer установлен"
}

# =====================================================
# 6. Создание пользователя для приложения
# =====================================================
create_app_user() {
    print_step "Создание пользователя app"
    
    if id "app" &>/dev/null; then
        print_info "Пользователь app уже существует"
    else
        useradd -m -s /bin/bash app
        echo "app:$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)" | chpasswd
        print_success "Пользователь app создан"
    fi
    
    # Добавляем в sudo (для kubectl)
    usermod -aG sudo app
    echo "app ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/app
    
    # Генерируем SSH ключ для деплоя
    if [ ! -f /home/app/.ssh/id_ed25519 ]; then
        mkdir -p /home/app/.ssh
        ssh-keygen -t ed25519 -N "" -f /home/app/.ssh/id_ed25519 -C "app@pigeongram"
        chown -R app:app /home/app/.ssh
    fi
}

# =====================================================
# 7. Настройка фаервола (UFW)
# =====================================================
setup_firewall() {
    print_step "Настройка фаервола"
    
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    
    ufw allow 22/tcp comment 'SSH'
    ufw allow 80/tcp comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'
    ufw allow 6443/tcp comment 'k3s API'
    ufw allow 30777/tcp comment 'Portainer'
    
    # NodePort для ingress (если используется)
    ufw allow 30080/tcp comment 'Ingress HTTP'
    ufw allow 30443/tcp comment 'Ingress HTTPS'
    
    echo "y" | ufw enable
    print_success "Фаервол настроен"
}

# =====================================================
# 8. Настройка fail2ban
# =====================================================
setup_fail2ban() {
    print_step "Настройка fail2ban"
    
    cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
maxretry = 3
EOF

    systemctl restart fail2ban
    systemctl enable fail2ban
    print_success "fail2ban настроен"
}

# =====================================================
# 9. Настройка автоматических обновлений
# =====================================================
setup_auto_updates() {
    print_step "Настройка автоматических обновлений"
    
    cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

    systemctl restart unattended-upgrades
    print_success "Автоматические обновления настроены"
}

# =====================================================
# 10. Настройка swap
# =====================================================
setup_swap() {
    print_step "Настройка swap"
    
    if swapon --show | grep -q "/swapfile"; then
        print_info "Swap уже настроен"
        return 0
    fi
    
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
    sysctl vm.swappiness=10
    echo "vm.swappiness=10" >> /etc/sysctl.conf
    
    print_success "Swap создан (2GB)"
}

# =====================================================
# 11. Создание директорий для проекта
# =====================================================
create_directories() {
    print_step "Создание директорий для проекта"
    
    mkdir -p /opt/pigeongram-chat
    mkdir -p /opt/pigeongram-infra
    mkdir -p /backups
    
    chown -R app:app /opt/pigeongram-chat
    chown -R app:app /opt/pigeongram-infra
    chown -R app:app /backups
    
    print_success "Директории созданы"
}

# =====================================================
# 12. Установка Go (для сборки если нужно)
# =====================================================
install_go() {
    print_step "Установка Go"
    
    if command -v go &> /dev/null; then
        print_info "Go уже установлен"
        return 0
    fi
    
    GO_VERSION="1.26.1"
    ARCH=$(uname -m)
    [ "$ARCH" = "x86_64" ] && GO_ARCH="amd64" || GO_ARCH="arm64"
    
    wget -q "https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
    rm -rf /usr/local/go
    tar -C /usr/local -xzf "go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
    rm "go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
    
    echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
    echo 'export PATH=$PATH:/usr/local/go/bin' >> /home/app/.bashrc
    
    print_success "Go установлен"
}

# =====================================================
# 13. Проверка установки
# =====================================================
verify_installation() {
    print_step "Проверка установки"
    
    echo ""
    echo "📦 Версии:"
    echo "   k3s: $(k3s --version 2>/dev/null | head -1 || echo 'не установлен')"
    echo "   Helm: $(helm version --short 2>/dev/null || echo 'не установлен')"
    echo "   Go: $(/usr/local/go/bin/go version 2>/dev/null || echo 'не установлен')"
    echo "   Git: $(git --version 2>/dev/null || echo 'не установлен')"
    echo ""
    
    echo "🔌 Службы:"
    echo "   k3s: $(systemctl is-active k3s 2>/dev/null || echo 'не активен')"
    echo "   fail2ban: $(systemctl is-active fail2ban)"
    echo ""
    
    echo "🚪 Portainer:"
    echo "   URL: http://$(hostname -I | awk '{print $1}'):30777"
    echo ""
    
    echo "🔑 SSH публичный ключ (для GitHub):"
    cat /home/app/.ssh/id_ed25519.pub
    echo ""
}

# =====================================================
# 14. Установка kubectl (уже есть в k3s, но делаем алиас)
# =====================================================
setup_kubectl() {
    print_step "Настройка kubectl"
    
    echo 'alias k="kubectl"' >> /root/.bashrc
    echo 'source <(kubectl completion bash)' >> /root/.bashrc
    echo 'complete -F __start_kubectl k' >> /root/.bashrc
    
    print_success "kubectl настроен"
}

# =====================================================
# Главная функция
# =====================================================
main() {
    print_header "PigeonGram - Инициализация сервера"
    
    check_root
    
    update_system
    install_base_packages
    create_app_user
    install_k3s
    install_helm
    install_portainer
    setup_kubectl
    setup_firewall
    setup_fail2ban
    setup_auto_updates
    setup_swap
    install_go
    create_directories
    verify_installation
    
    print_header "Инициализация завершена!"
    
    echo ""
    echo "📋 Следующие шаги:"
    echo ""
    echo "1. Добавь SSH ключ в GitHub (выше в выводе):"
    echo "   https://github.com/settings/keys"
    echo ""
    echo "2. Войди под пользователем app:"
    echo "   su - app"
    echo ""
    echo "3. Клонируй репозитории:"
    echo "   git clone git@github.com:PavlovVitaly/pigeongram-chat.git /opt/pigeongram-chat"
    echo "   git clone git@github.com:PavlovVitaly/pigeongram-infra.git /opt/pigeongram-infra"
    echo ""
    echo "4. Задеплой инфраструктуру:"
    echo "   cd /opt/pigeongram-infra"
    echo "   ./scripts/deploy.sh"
    echo ""
    echo "5. Portainer доступен на:"
    echo "   http://$(hostname -I | awk '{print $1}'):30777"
    echo ""
}

main "$@"