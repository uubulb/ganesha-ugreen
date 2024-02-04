#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

exit_status=$?

INSTALL_DIR=/opt

GITHUB_URL=https://github.com
GITHUB_RAW_URL=https://raw.githubusercontent.com
GITHUB_PROXY=https://mirror.ghproxy.com/

update_script() {
    echo "正在更新脚本"
    wget -qO /tmp/ganesha.sh ${GITHUB_PROXY}$GITHUB_RAW_URL/uubulb/ganesha-ugreen/main/ganesha.sh
    mv -f /tmp/ganesha.sh ./ganesha.sh && chmod a+x ./ganesha.sh
    echo -e "3s后执行新脚本"
    sleep 3s
    clear
    exec ./ganesha.sh
    exit 0
}

install() {
    echo "正在安装 nfs-ganesha"
    if [ -f "${INSTALL_DIR}/bin/ganesha.nfsd" ]; then
        echo "您可能已经安装过 nfs-ganesha，重复安装会清空数据，请注意备份。"
        read -e -r -p "是否退出安装? [Y/n] " input
        case $input in
        [yY][eE][sS] | [yY])
            echo "退出安装"
            exit 0
            ;;
        [nN][oO] | [nN])
            echo "继续安装"
            ;;
        *)
            echo "退出安装"
            exit 0
            ;;
        esac
    fi
    if [[ $(uname -m | grep 'x86_64') != "" ]]; then
        os_arch="amd64"
    elif [[ $(uname -m | grep 'aarch64\|armv8b\|armv8l') != "" ]]; then
        os_arch="arm64"
    fi
    DOWNLOAD_URL=${GITHUB_PROXY}${GITHUB_URL}/uubulb/ganesha-ugreen/releases/download/binary/nfs-ganesha_5.7_${os_arch}.tar.gz
    wget -qO- $DOWNLOAD_URL | tar -C $INSTALL_DIR -xzf -
    mkdir -p $INSTALL_DIR/var/run/ganesha
    if [ $exit_status -eq 0 ]; then
        echo -e "${yellow}安装成功！开始配置。${plain}"
        modify_config
        echo -e "${yellow}配置过程结束，下载服务文件并启动 nfs-ganesha${plain}"
        wget -qO $INSTALL_DIR/etc/ganesha/S80ganesha ${GITHUB_PROXY}${GITHUB_RAW_URL}/uubulb/ganesha-ugreen/main/S80ganesha
        chmod +x $INSTALL_DIR/etc/ganesha/S80ganesha && ln -s $INSTALL_DIR/etc/ganesha/S80ganesha /etc/init.d/S80ganesha
        /etc/init.d/S80ganesha enable && /etc/init.d/S80ganesha start
        echo -e "${green}nfs-ganesha 已成功启动${plain}"
    else
        echo -e "${red}安装失败，可能是网络问题${plain}"
    fi
}

preconfig() {
    DISK_COUNT=$(ls /mnt/media_rw | sed 's|^|/mnt/media_rw/|' | wc -l)
    for ((num = 1; num <= DISK_COUNT; num++)); do
        find /mnt/media_rw | sed '1d' | sed -n "${num}p" | xargs readlink >> /tmp/diskcount.txt
    done
    for ((num = 1; num <= DISK_COUNT; num++)); do
        local DISK_NAME=$(sed -n '/######### Dynamic written config options #########/,${p;/#########/d}' /etc/samba/smb.conf | grep "\[" | sed -n "${num}p" | awk -F'[][]' '/\[.*\]/{sub("^[^_]+_", "", $2); print $2}')
        local INTERNAL_NAME=$(sed -n '/######### Dynamic written config options #########/,${p;/#########/d}' /etc/samba/smb.conf | grep path | sed -n "${num}p" | awk -F'/' '/path/{sub("^.*dm-", "", $4); print $3}')
        eval "$DISK_NAME=$INTERNAL_NAME"
    done
    DISK_LIST=$(sed -n '/######### Dynamic written config options #########/,${p;/#########/d}' /etc/samba/smb.conf | grep "\[" | awk -F'[][]' '/\[.*\]/{sub("^[^_]+_", "", $2); print $2}' | tr '\n' ' ')
    ID=$(cat /etc/passwd | grep "UGreen User" | awk -F: '{print $3}')
}

modify_config() {
    preconfig
    echo -e "您目前有 ${green}$DISK_COUNT${plain} 个硬盘，您的 UID 为 ${green}$ID${plain}"
    if [ -f "$INSTALL_DIR/etc/ganesha/ganesha.conf" ]; then
        echo "已找到配置文件，请确保配置中相关标记未被删除，再使用本脚本修改配置"
    else
        echo "配置文件不存在，将按照流程为您创建"
        FRESH_INSTALL=1
    fi
    if [[ ! $FRESH_INSTALL == 1 ]]; then
        EXPORT_COUNT=$(sed -n '/# BEGIN EXPORT/,/# END EXPORT/p' $INSTALL_DIR/etc/ganesha/ganesha.conf | grep "## BEGIN EXPORT" | wc -l)
        if [ -z "$EXPORT_COUNT" ]; then
            local EXPORT_COUNT=0
        fi
        echo -e "已找到配置 ${green}$EXPORT_COUNT${plain} 个"
    else
        echo "下载配置模板……"
        wget -qO $INSTALL_DIR/etc/ganesha/ganesha.conf.template ${GITHUB_PROXY}${GITHUB_RAW_URL}/uubulb/ganesha-ugreen/main/ganesha.conf.template
    fi
    echo -e "
    ${yellow}请选择操作：${plain}
    ${yellow}1.${plain}  添加新的共享目录
    ${yellow}2.${plain}  删除共享目录
    ${yellow}0.${plain}  退出
    "
    echo && read -ep "请输入选择 [0-2]: " num
    
    case "${num}" in
        0)
            exit 0
        ;;
        1)
            EXPORT_NUM=$((EXPORT_COUNT + 1))
            echo -e "${yellow}请输入以下 EXPORT 全局配置${plain}"
            read -ep "输入 EXPORT 权限: (RW, RO, None)" EXPORT_PERM
            read -ep "输入 Squash 类型 (All, None, Root): " SQUASH
            read -ep "输入共享盘名称: ($DISK_LIST): " EXPORT_DISK
            read -ep "输入共享文件夹路径: (例如 download/download ): " EXPORT_DIR
            read -ep "输入显示路径: (默认同真实路径) " PSEUDO
            if [[ -z "${EXPORT_PERM}" || -z "${SQUASH}" || -z "${EXPORT_DISK}" || -z "${EXPORT_DIR}" ]]; then
                echo -e "${red}所有选项都不能为空${plain}"
                return 1
            fi
            REAL_PATH="/mnt/${!EXPORT_DISK}/.ugreen_nas/$(echo $ID | sed 's/0000$//')/${EXPORT_DIR}"
            if [[ -z "${PSEUDO}" ]]; then
                PSEUDO="${REAL_PATH}"
            fi
            echo -e "${yellow}请输入以下 EXPORT 客户端配置${plain}"
            read -ep "输入客户端 IP 范围: (e.g. 192.168.1.0/24)" IP_RANGE
            read -ep "输入客户端 Squash 类型 (All, None, Root): " CLIENT_SQUASH
            read -ep "输入客户端权限: (RW, RO, None) " CLIENT_PERM
            if [[ -z "${IP_RANGE}" || -z "${CLIENT_SQUASH}" || -z "${CLIENT_PERM}" ]]; then
                echo -e "${red}所有选项都不能为空${plain}"
                return 1
            fi
            if [[ -z "${CLIENT_NUM}" ]]; then
                CLIENT_NUM=1
            fi
            CLIENT="
### BEGIN CLIENT $CLIENT_NUM
CLIENT
	{
		Clients = ${IP_RANGE};
		Squash = ${CLIENT_SQUASH};
		Access_Type = ${CLIENT_PERM};
		Anonymous_Uid = ${ID};
		Anonymous_Gid = ${ID};
	}
### END CLIENT $CLIENT_NUM
"
            read -e -r -p "客户端添加完毕，是否再继续添加新的客户端？[y/N]" input
            case $input in
            [yY][eE][sS] | [yY])
                local ADD_CONFIG=1
                while [[ "${ADD_CONFIG}" -eq 1 ]]; do
                    echo -e "请输入以下 EXPORT 客户端配置"
                    read -ep "输入客户端 IP 范围: (例如 192.168.1.0/24)" IP_RANGE_EXTRA
                    read -ep "输入客户端 Squash 类型 (All, None, Root): " CLIENT_SQUASH_EXTRA
                    read -ep "输入客户端权限: (RW, RO, None) " CLIENT_PERM_EXTRA
                    if [[ -z "${IP_RANGE_EXTRA}" || -z "${CLIENT_SQUASH_EXTRA}" || -z "${CLIENT_PERM_EXTRA}" ]]; then
                        echo -e "${red}所有选项都不能为空${plain}"
                        return 1
                    fi
                    ((CLIENT_NUM++))
                    CLIENT_EXTRA="
### BEGIN CLIENT $CLIENT_NUM
CLIENT
	{
		Clients = ${IP_RANGE_EXTRA};
		Squash = ${CLIENT_SQUASH_EXTRA};
		Access_Type = ${CLIENT_PERM_EXTRA};
		Anonymous_Uid = ${ID};
		Anonymous_Gid = ${ID};
	}
### END CLIENT $CLIENT_NUM
"
                    CLIENT="${CLIENT}
${CLIENT_EXTRA}"
                    read -e -r -p "客户端添加完毕，是否再继续添加新的客户端？[y/N]" input
                    case $input in
                    [yY][eE][sS] | [yY])
                        local ADD_CONFIG=1
                    ;;
                    [nN][oO] | [nN])
                        echo "结束客户端配置"
                        local ADD_CONFIG=0
                    ;;
                    *)
                        echo "结束客户端配置"
                        local ADD_CONFIG=0
                    ;;
                    esac
                done
            ;;
            [nN][oO] | [nN])
                echo "结束客户端配置"
            ;;
            *)
                echo "结束客户端配置"
            ;;
            esac
            export EXPORT_CFG="
## BEGIN EXPORT $EXPORT_NUM
EXPORT
{
	Export_Id = ${EXPORT_NUM};

	Path = ${REAL_PATH};

	Pseudo = ${PSEUDO};

	Protocols = 3,4;

	Access_Type = ${EXPORT_PERM};

	Squash = ${SQUASH};

	$CLIENT

	Sectype = sys;

	FSAL {
		Name = VFS;
	}
}
## END EXPORT $EXPORT_NUM
"
            if [[ $EXPORT_COUNT == 0 ]]; then
                awk '{gsub(/#! END EXPORT/, ENVIRON["EXPORT_CFG"] "\n#! END EXPORT")}1' $INSTALL_DIR/etc/ganesha/ganesha.conf.template > $INSTALL_DIR/etc/ganesha/ganesha.conf
            else
                awk '{gsub(/#! END EXPORT/, ENVIRON["EXPORT_CFG"] "\n#! END EXPORT")}1' $INSTALL_DIR/etc/ganesha/ganesha.conf > /tmp/ganesha.conf.tmp
                mv /tmp/ganesha.conf.tmp $INSTALL_DIR/etc/ganesha/ganesha.conf
            fi
            echo -e "${green}已成功创建 EXPORT #${EXPORT_NUM}${plain}"
            read -e -r -p "配置需要重启nfs-ganesha后生效，是否现在重启? [Y/n]" input
            case $input in
            [yY][eE][sS] | [yY])
                if [ -f /etc/init.d/S80ganesha ]; then
                    /etc/init.d/S80ganesha restart
                elif [[ -f $INSTALL_DIR/etc/ganesha/S80ganesha ]] && [ ! -f /etc/init.d/S80ganesha ]; then
                    ln -s $INSTALL_DIR/etc/ganesha/S80ganesha /etc/init.d/S80ganesha
                    /etc/init.d/S80ganesha restart
                fi
                exit 0
            ;;
            [nN][oO] | [nN])
                echo -e "${yellow}稍后如需重启，请在脚本菜单中选择先关闭再启动${plain}"
                exit 0
            ;;
            *)
                if [ -f /etc/init.d/S80ganesha ]; then
                    /etc/init.d/S80ganesha restart
                elif [[ -f $INSTALL_DIR/etc/ganesha/S80ganesha ]] && [ ! -f /etc/init.d/S80ganesha ]; then
                    ln -s $INSTALL_DIR/etc/ganesha/S80ganesha /etc/init.d/S80ganesha
                    /etc/init.d/S80ganesha restart
                fi
                exit 0
            ;;
            esac
        ;;
        2)
            read -ep "输入需要删除的 EXPORT 序号 (忘了的话，请手动查看配置) : " DELETE_NUM
            sed -e "/## BEGIN EXPORT $DELETE_NUM/,/## END EXPORT $DELETE_NUM/d" $INSTALL_DIR/etc/ganesha/ganesha.conf > /tmp/ganesha.conf.tmp
            mv /tmp/ganesha.conf.tmp $INSTALL_DIR/etc/ganesha/ganesha.conf
            echo -e "已删除 EXPORT #$DELETE_NUM"
            read -e -r -p "配置需要重启nfs-ganesha后生效，是否现在重启? [Y/n]" input
            case $input in
            [yY][eE][sS] | [yY])
                if [ -f /etc/init.d/S80ganesha ]; then
                    /etc/init.d/S80ganesha restart
                elif [[ -f $INSTALL_DIR/etc/ganesha/S80ganesha ]] && [ ! -f /etc/init.d/S80ganesha ]; then
                    ln -s $INSTALL_DIR/etc/ganesha/S80ganesha /etc/init.d/S80ganesha
                    /etc/init.d/S80ganesha restart
                fi
                exit 0
            ;;
            [nN][oO] | [nN])
                echo -e "${yellow}稍后如需重启，请在脚本菜单中选择先关闭再启动${plain}"
                exit 0
            ;;
            *)
                if [ -f /etc/init.d/S80ganesha ]; then
                    /etc/init.d/S80ganesha restart
                elif [[ -f $INSTALL_DIR/etc/ganesha/S80ganesha ]] && [ ! -f /etc/init.d/S80ganesha ]; then
                    ln -s $INSTALL_DIR/etc/ganesha/S80ganesha /etc/init.d/S80ganesha
                    /etc/init.d/S80ganesha restart
                fi
                exit 0
            ;;
            esac
        ;;
        *)
            echo -e "${red}请输入正确的数字 [0-2]${plain}"
        ;;
    esac
}

uninstall() {
    echo -e "${yellow}开始卸载nfs-ganesha${plain}"
    if [[ -f $INSTALL_DIR/var/run/ganesha/ganesha.pid ]]; then
        /etc/init.d/S80ganesha stop
    else
        kill -9 $(ps aux | grep '[g]anesha.nfsd' | awk '{print $2}') >/dev/null 2>&1
    fi
    echo -e "$INSTALL_DIR/lib/pkgconfig/libntirpc.pc\n$INSTALL_DIR/lib/ganesha/\n$INSTALL_DIR/lib/libacl.so.1\n$INSTALL_DIR/lib/liburcu-bp.so.8\n$INSTALL_DIR/lib/libganesha_nfsd.so.5.7\n$INSTALL_DIR/lib/libntirpc.so.5.0\n$INSTALL_DIR/lib/libganesha_nfsd.so\n$INSTALL_DIR/lib/libntirpc.so\n$INSTALL_DIR/bin/ganesha.nfsd\n$INSTALL_DIR/etc/ganesha/\n$INSTALL_DIR/include/ntirpc/\n/etc/init.d/S80ganesha\n$INSTALL_DIR/var/run/ganesha/\n$INSTALL_DIR/var/log/ganesha.log" | xargs rm -rf
    echo -e "${yellow}卸载过程结束${plain}"
}

stop() {
    if [[ -f $INSTALL_DIR/var/run/ganesha/ganesha.pid ]]; then
        /etc/init.d/S80ganesha stop
    else
        kill -9 $(ps aux | grep '[g]anesha.nfsd' | awk '{print $2}') >/dev/null 2>&1
    fi
}

show_menu() {
    echo -e "
    ${yellow}欢迎使用 nfs-ganesha 管理脚本${plain}
    ${yellow}请选择选项：${plain}
    ${yellow}1.${plain}  安装 nfs-ganesha
    ${yellow}2.${plain}  管理挂载目录
    ${yellow}3.${plain}  卸载 nfs-ganesha
    ${yellow}4.${plain}  启动 nfs-ganesha
    ${yellow}5.${plain}  关闭 nfs-ganesha
    ${yellow}6.${plain}  查看配置
    ${yellow}7.${plain}  更新脚本
    ${yellow}0.${plain}  退出脚本
    "
    echo && read -ep "请输入选择 [0-7]: " num
    
    case "${num}" in
        0)
            exit 0
        ;;
        1)
            install
        ;;
        2)
            modify_config
        ;;
        3)
            uninstall
        ;;
        4)
            if [ -f /etc/init.d/S80ganesha ]; then
                /etc/init.d/S80ganesha start
            elif [[ -f $INSTALL_DIR/etc/ganesha/S80ganesha ]] && [ ! -f /etc/init.d/S80ganesha ]; then
                ln -s $INSTALL_DIR/etc/ganesha/S80ganesha /etc/init.d/S80ganesha
                /etc/init.d/S80ganesha start
            else
                echo -e "${red}您似乎还没有安装 nfs-ganesha${plain}"
            fi
        ;;
        5)
            if [ -f /etc/init.d/S80ganesha ]; then
                stop
            elif [[ -f $INSTALL_DIR/etc/ganesha/S80ganesha ]] && [-f /etc/init.d/S80ganesha ]; then
                ln -s $INSTALL_DIR/etc/ganesha/S80ganesha /etc/init.d/S80ganesha
                stop
            else
                echo -e "${red}您似乎还没有安装 nfs-ganesha${plain}"
            fi
        ;;
        6)
            less $INSTALL_DIR/etc/ganesha/ganesha.conf
        ;;
        7)
            update_script
        ;;
        *)
            echo -e "${red}请输入正确的数字 [0-7]${plain}"
        ;;
    esac
}

show_menu