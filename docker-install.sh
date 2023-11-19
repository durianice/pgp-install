#!/usr/bin/env bash

# 检查是否以 root 权限运行脚本
check_root () {
    if [[ $EUID -ne 0 ]]; then
        echo "错误：本脚本需要 root 权限执行。" 1>&2
        exit 1
    fi
}

# 检查 Docker 是否安装
docker_check () {
    if ! command -v docker &>/dev/null; then
        echo "Docker 未安装在此系统上"
        echo "请安装 Docker 并将自己添加到 Docker 分组并重新运行此脚本。"
        exit 1
    fi
}

# 检查是否有访问 Docker 的权限
access_check () {
    if ! [ -w /var/run/docker.sock ]; then
        echo "该用户无权访问 Docker，或者 Docker 没有运行。请添加自己到 Docker 分组并重新运行此脚本。"
        exit 1
    fi
}

# 拉取 Docker 镜像并移除同名的旧容器
build_docker () {
    printf "请输入 PagerMaid 容器的名称："
    read -r container_name <&1
    echo "正在拉取 Docker 镜像 . . ."
    docker rm -f "$container_name" &>/dev/null
    docker pull teampgm/pagermaid_pyro
}

# 询问是否需要设置 Web 管理界面
need_web () {
    PGM_WEB=false
    printf "请问是否需要启用 Web 管理界面 [Y/n] ："
    read -r web <&1
    case $web in
        [yY][eE][sS]|[yY])
            PGM_WEB=true
            printf "请输入管理员密码（如果不需要密码请直接回车）："
            read -r admin_password <&1
            ;;
        [nN][oO]|[nN]|"")
            ;;
        *)
            echo "输入错误，已跳过。"
            ;;
    esac
}

# 询问是否需要设置 Web 登录界面
need_web_login () {
    PGM_WEB_LOGIN=false
    if [[ $PGM_WEB == true ]]; then
        printf "请问是否需要启用 Web 登录界面 [Y/n] ："
        read -r web_login <&1
        case $web_login in
            [yY][eE][sS]|[yY])
                PGM_WEB_LOGIN=true
                ;;
            [nN][oO]|[nN]|"")
                ;;
            *)
                echo "输入错误，已跳过。"
                ;;
        esac
    fi
}

# 启动 Docker 容器
start_docker () {
    echo "正在启动 Docker 容器 . . ."
    local docker_run_command="docker run -dit --restart=always --name=\"$container_name\" --hostname=\"$container_name\""
    if [[ $PGM_WEB == true ]]; then
        docker_run_command+=" -e WEB_ENABLE=\"$PGM_WEB\" -e WEB_SECRET_KEY=\"$admin_password\" -e WEB_HOST=0.0.0.0 -e WEB_PORT=3333 -e WEB_LOGIN=\"$PGM_WEB_LOGIN\" -p 3333:3333"
    fi
    docker_run_command+=" teampgm/pagermaid_pyro"
    eval $docker_run_command <&1

    post_start_setup
}

# 启动后的设置
post_start_setup () {
    echo
    echo "开始配置参数 . . ."
    echo "在登录后，请按 Ctrl + C 使容器在后台模式下重新启动。"
    sleep 3
    docker exec -it "$container_name" bash utils/docker-config.sh
    echo
    echo "Docker 重启中，如果失败，请手动重启容器。"
    echo
    docker restart "$container_name"
    echo
    echo "Docker 创建完毕。"
    echo
}

# 确保数据持久化
data_persistence () {
    while true; do
        printf "请输入将数据保留在宿主机哪个路径（绝对路径），同时请确保该路径下没有名为 workdir 的文件夹 ："
        read -r data_path <&1
        if [[ -d "$data_path" ]]; then
            break
        else
            echo "路径 $data_path 不存在，请重新输入。"
        fi
    done

    # 以下是数据持久化的逻辑
    if [[ -z $container_name ]]; then
        printf "请输入 PagerMaid 容器的名称："
        read -r container_name <&1
    fi
    if docker inspect "$container_name" &>/dev/null; then
        docker cp "$container_name":/pagermaid/workdir "$data_path"
        docker stop "$container_name" &>/dev/null
        docker rm "$container_name" &>/dev/null
        local docker_run_command="docker run -dit -v \"$data_path/workdir\":/pagermaid/workdir --restart=always --name=\"$container_name\" --hostname=\"$container_name\""
        if [[ $PGM_WEB == true ]]; then
            docker_run_command+=" -e WEB_ENABLE=\"$PGM_WEB\" -e WEB_SECRET_KEY=\"$admin_password\" -e WEB_HOST=0.0.0.0 -e WEB_PORT=3333 -p 3333:3333"
        fi
        docker_run_command+=" teampgm/pagermaid_pyro"
        eval $docker_run_command <&1
        echo
        echo "数据持久化操作完成。"
        echo
    else
        echo "不存在名为 $container_name 的容器，退出。"
    fi
}

# 显示菜单并处理用户输入
shon_online () {
    echo "欢迎使用 PagerMaid-Pyro Docker 一键安装脚本。"
    echo
    echo "请选择您需要进行的操作:"
    echo "  1) Docker 安装 PagerMaid"
    echo "  2) Docker 卸载 PagerMaid"
    echo "  3) Docker 关闭 PagerMaid"
    echo "  4) Docker 启动 PagerMaid"
    echo "  5) Docker 重启 PagerMaid"
    echo "  6) Docker 重装 PagerMaid"
    echo "  7) 持久化数据"
    echo "  8) 退出脚本"
    echo
    echo "     Version：2.2.0"
    echo
    echo -n "请输入编号: "
    read -r N <&1
    case $N in
        1)
            start_installation
            ;;
        2)
            cleanup
            ;;
        3)
            stop_pager
            ;;
        4)
            start_pager
            ;;
        5)
            restart_pager
            ;;
        6)
            reinstall_pager
            ;;
        7)
            data_persistence
            ;;
        8)
            exit 0
            ;;
        *)
            echo "输入错误！"
            sleep 5s
            shon_online
            ;;
    esac
}

# 主脚本执行
check_root
shon_online
