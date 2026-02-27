#!/bin/bash
set -e

export LANG=en_US.UTF-8
export LC_ALL=C

REPO_URL="https://github.com/xiaoxinmm/flux-panel-community.git"
INSTALL_DIR="flux-panel-community"

COUNTRY=$(curl -s https://ipinfo.io/country)
if [ "$COUNTRY" = "CN" ]; then
    REPO_URL="https://ghfast.top/${REPO_URL}"
fi

# 检查 docker-compose 或 docker compose 命令
check_docker() {
  if command -v docker-compose &> /dev/null; then
    DOCKER_CMD="docker-compose"
  elif command -v docker &> /dev/null; then
    if docker compose version &> /dev/null; then
      DOCKER_CMD="docker compose"
    else
      echo "错误：检测到 docker，但不支持 'docker compose' 命令。请安装 docker-compose 或更新 docker 版本。"
      exit 1
    fi
  else
    echo "错误：未检测到 docker 或 docker-compose 命令。请先安装 Docker。"
    exit 1
  fi
  echo "检测到 Docker 命令：$DOCKER_CMD"
}

# 检查 git
check_git() {
  if ! command -v git &> /dev/null; then
    echo "错误：未检测到 git，请先安装 git。"
    exit 1
  fi
}

# 检测系统是否支持 IPv6
check_ipv6_support() {
  if ip -6 addr show 2>/dev/null | grep -v "scope link" | grep -q "inet6"; then
    return 0
  elif ifconfig 2>/dev/null | grep -v "fe80:" | grep -q "inet6"; then
    return 0
  else
    return 1
  fi
}

# 配置 Docker 启用 IPv6
configure_docker_ipv6() {
  echo "🔧 配置 Docker IPv6 支持..."
  OS_TYPE=$(uname -s)
  if [[ "$OS_TYPE" == "Darwin" ]]; then
    echo "✅ macOS Docker Desktop 默认支持 IPv6"
    return 0
  fi

  DOCKER_CONFIG="/etc/docker/daemon.json"
  if [[ $EUID -ne 0 ]]; then SUDO_CMD="sudo"; else SUDO_CMD=""; fi

  if [ -f "$DOCKER_CONFIG" ]; then
    if grep -q '"ipv6"' "$DOCKER_CONFIG"; then
      echo "✅ Docker 已配置 IPv6 支持"
    else
      $SUDO_CMD cp "$DOCKER_CONFIG" "${DOCKER_CONFIG}.backup"
      if command -v jq &> /dev/null; then
        $SUDO_CMD jq '. + {"ipv6": true, "fixed-cidr-v6": "fd00::/80"}' "$DOCKER_CONFIG" > /tmp/daemon.json && $SUDO_CMD mv /tmp/daemon.json "$DOCKER_CONFIG"
      else
        $SUDO_CMD sed -i 's/^{$/{\n  "ipv6": true,\n  "fixed-cidr-v6": "fd00::\/80",/' "$DOCKER_CONFIG"
      fi
      if command -v systemctl &> /dev/null; then $SUDO_CMD systemctl restart docker
      elif command -v service &> /dev/null; then $SUDO_CMD service docker restart
      else echo "⚠️ 请手动重启 Docker 服务"; fi
      sleep 5
    fi
  else
    $SUDO_CMD mkdir -p /etc/docker
    echo '{ "ipv6": true, "fixed-cidr-v6": "fd00::/80" }' | $SUDO_CMD tee "$DOCKER_CONFIG" > /dev/null
    if command -v systemctl &> /dev/null; then $SUDO_CMD systemctl restart docker
    elif command -v service &> /dev/null; then $SUDO_CMD service docker restart
    else echo "⚠️ 请手动重启 Docker 服务"; fi
    sleep 5
  fi
}

# 选择 docker-compose 文件
get_compose_file() {
  if check_ipv6_support; then
    echo "docker-compose-v6.yml"
  else
    echo "docker-compose-v4.yml"
  fi
}

show_menu() {
  echo "==============================================="
  echo "     flux-panel-community 面板管理脚本"
  echo "==============================================="
  echo "请选择操作："
  echo "1. 安装面板"
  echo "2. 更新面板"
  echo "3. 卸载面板"
  echo "4. 导出备份"
  echo "5. 退出"
  echo "==============================================="
}

generate_random() {
  LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c16
}

delete_self() {
  echo ""
  echo "🗑️ 操作已完成，正在清理脚本文件..."
  SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"
  sleep 1
  rm -f "$SCRIPT_PATH" && echo "✅ 脚本文件已删除" || echo "❌ 删除脚本文件失败"
}

get_config_params() {
  echo "🔧 请输入配置参数："
  read -p "前端端口（默认 6366）: " FRONTEND_PORT
  FRONTEND_PORT=${FRONTEND_PORT:-6366}
  read -p "后端端口（默认 6365）: " BACKEND_PORT
  BACKEND_PORT=${BACKEND_PORT:-6365}
  DB_NAME=$(generate_random)
  DB_USER=$(generate_random)
  DB_PASSWORD=$(generate_random)
  JWT_SECRET=$(generate_random)
}

# 安装功能
install_panel() {
  echo "🚀 开始安装面板..."
  check_docker
  check_git
  get_config_params

  echo "🔽 克隆项目仓库..."
  if [[ -d "$INSTALL_DIR" ]]; then
    echo "⚠️ 目录 $INSTALL_DIR 已存在，拉取最新代码..."
    cd "$INSTALL_DIR"
    git pull
  else
    git clone "$REPO_URL" "$INSTALL_DIR"
    cd "$INSTALL_DIR"
  fi

  COMPOSE_FILE=$(get_compose_file)
  echo "📡 使用配置文件：$COMPOSE_FILE"
  cp "$COMPOSE_FILE" docker-compose.yml

  if check_ipv6_support; then
    echo "🚀 系统支持 IPv6，自动启用 IPv6 配置..."
    configure_docker_ipv6
  fi

  cat > .env <<EOF
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
JWT_SECRET=$JWT_SECRET
FRONTEND_PORT=$FRONTEND_PORT
BACKEND_PORT=$BACKEND_PORT
EOF

  echo "🔨 构建并启动服务（首次构建可能需要几分钟）..."
  $DOCKER_CMD up -d --build

  echo "🎉 部署完成"
  echo "🌐 访问地址: http://服务器IP:$FRONTEND_PORT"
  echo "📚 文档地址: https://tes.cc/guide.html"
  echo "💡 默认管理员账号: admin_user / admin_user"
  echo "⚠️  登录后请立即修改默认密码！"
}

# 更新功能
update_panel() {
  echo "🔄 开始更新面板..."
  check_docker
  check_git

  if [[ ! -d "$INSTALL_DIR" ]]; then
    echo "❌ 未找到安装目录 $INSTALL_DIR，请先安装面板。"
    return 1
  fi

  cd "$INSTALL_DIR"

  echo "🔽 拉取最新代码..."
  git pull

  COMPOSE_FILE=$(get_compose_file)
  cp "$COMPOSE_FILE" docker-compose.yml

  if check_ipv6_support; then
    configure_docker_ipv6
  fi

  echo "🛑 停止当前服务..."
  $DOCKER_CMD down

  echo "🔨 重新构建并启动..."
  $DOCKER_CMD up -d --build

  # 等待服务启动
  echo "⏳ 等待服务启动..."
  echo "🔍 检查后端服务状态..."
  for i in {1..90}; do
    if docker ps --format "{{.Names}}" | grep -q "^springboot-backend$"; then
      BACKEND_HEALTH=$(docker inspect -f '{{.State.Health.Status}}' springboot-backend 2>/dev/null || echo "unknown")
      if [[ "$BACKEND_HEALTH" == "healthy" ]]; then
        echo "✅ 后端服务健康检查通过"
        break
      fi
    fi
    if [ $i -eq 90 ]; then
      echo "❌ 后端服务启动超时（90秒）"
      return 1
    fi
    if [ $((i % 15)) -eq 1 ]; then
      echo "⏳ 等待后端服务启动... ($i/90) 状态：${BACKEND_HEALTH:-unknown}"
    fi
    sleep 1
  done

  # 从容器环境变量获取数据库信息
  echo "🔍 获取数据库配置信息..."
  sleep 5

  if ! docker ps --format "{{.Names}}" | grep -q "^springboot-backend$"; then
    echo "❌ 后端容器未运行，无法获取数据库配置"
    return 1
  fi

  DB_INFO=$(docker exec springboot-backend env | grep "^DB_" 2>/dev/null || echo "")
  if [[ -n "$DB_INFO" ]]; then
    DB_NAME=$(echo "$DB_INFO" | grep "^DB_NAME=" | cut -d'=' -f2)
    DB_PASSWORD=$(echo "$DB_INFO" | grep "^DB_PASSWORD=" | cut -d'=' -f2)
    DB_USER=$(echo "$DB_INFO" | grep "^DB_USER=" | cut -d'=' -f2)
  elif [[ -f ".env" ]]; then
    DB_NAME=$(grep "^DB_NAME=" .env | cut -d'=' -f2 2>/dev/null)
    DB_PASSWORD=$(grep "^DB_PASSWORD=" .env | cut -d'=' -f2 2>/dev/null)
    DB_USER=$(grep "^DB_USER=" .env | cut -d'=' -f2 2>/dev/null)
  else
    echo "❌ 无法获取数据库配置"
    return 1
  fi

  if [[ -z "$DB_PASSWORD" || -z "$DB_USER" || -z "$DB_NAME" ]]; then
    echo "❌ 数据库配置不完整"
    return 1
  fi

  # 执行数据库迁移（保持原有迁移逻辑）
  echo "🔄 执行数据库结构更新..."
  if [[ -f "migrate.sql" ]]; then
    if docker exec -i gost-mysql mysql -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" < migrate.sql 2>/dev/null; then
      echo "✅ 数据库结构更新完成"
    else
      echo "⚠️ 数据库迁移可能需要手动执行 migrate.sql"
    fi
  fi

  echo "✅ 更新完成"
}

# 导出数据库备份
export_migration_sql() {
  echo "📄 开始导出数据库备份..."
  check_docker

  if [[ -f ".env" ]]; then
    DB_NAME=$(grep "^DB_NAME=" .env | cut -d'=' -f2 2>/dev/null)
    DB_PASSWORD=$(grep "^DB_PASSWORD=" .env | cut -d'=' -f2 2>/dev/null)
    DB_USER=$(grep "^DB_USER=" .env | cut -d'=' -f2 2>/dev/null)
  elif docker ps --format "{{.Names}}" | grep -q "^springboot-backend$"; then
    DB_INFO=$(docker exec springboot-backend env | grep "^DB_" 2>/dev/null || echo "")
    DB_NAME=$(echo "$DB_INFO" | grep "^DB_NAME=" | cut -d'=' -f2)
    DB_PASSWORD=$(echo "$DB_INFO" | grep "^DB_PASSWORD=" | cut -d'=' -f2)
    DB_USER=$(echo "$DB_INFO" | grep "^DB_USER=" | cut -d'=' -f2)
  else
    echo "❌ 无法获取数据库配置"
    return 1
  fi

  if [[ -z "$DB_PASSWORD" || -z "$DB_USER" || -z "$DB_NAME" ]]; then
    echo "❌ 数据库配置不完整"
    return 1
  fi

  if ! docker ps --format "{{.Names}}" | grep -q "^gost-mysql$"; then
    echo "❌ 数据库容器未运行"
    return 1
  fi

  SQL_FILE="database_backup_$(date +%Y%m%d_%H%M%S).sql"
  echo "📝 导出数据库备份: $SQL_FILE"

  if docker exec gost-mysql mysqldump -u "$DB_USER" -p"$DB_PASSWORD" --single-transaction --routines --triggers "$DB_NAME" > "$SQL_FILE" 2>/dev/null; then
    echo "✅ 数据库导出成功"
  elif docker exec gost-mysql mysqldump -u root -p"$DB_PASSWORD" --single-transaction --routines --triggers "$DB_NAME" > "$SQL_FILE" 2>/dev/null; then
    echo "✅ 数据库导出成功"
  else
    echo "❌ 数据库导出失败"
    rm -f "$SQL_FILE"
    return 1
  fi

  FILE_SIZE=$(du -h "$SQL_FILE" | cut -f1)
  echo "📁 文件位置: $(pwd)/$SQL_FILE"
  echo "📊 文件大小: $FILE_SIZE"
}

# 卸载功能
uninstall_panel() {
  echo "🗑️ 开始卸载面板..."
  check_docker

  if [[ -d "$INSTALL_DIR" ]]; then
    cd "$INSTALL_DIR"
  fi

  if [[ ! -f "docker-compose.yml" ]]; then
    echo "⚠️ 未找到 docker-compose.yml"
    return 1
  fi

  read -p "确认卸载面板吗？此操作将停止并删除所有容器和数据 (y/N): " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "❌ 取消卸载"
    return 0
  fi

  $DOCKER_CMD down --volumes --remove-orphans
  cd ..
  rm -rf "$INSTALL_DIR"
  echo "✅ 卸载完成"
}

# 主逻辑
main() {
  while true; do
    show_menu
    read -p "请输入选项 (1-5): " choice
    case $choice in
      1) install_panel; delete_self; exit 0 ;;
      2) update_panel; delete_self; exit 0 ;;
      3) uninstall_panel; delete_self; exit 0 ;;
      4) export_migration_sql; delete_self; exit 0 ;;
      5) echo "👋 退出脚本"; delete_self; exit 0 ;;
      *) echo "❌ 无效选项，请输入 1-5"; echo "" ;;
    esac
  done
}

main
