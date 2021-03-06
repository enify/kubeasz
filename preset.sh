#!/bin/bash
# 本脚本主要用于在安装k8s前在deploy节点上执行一些预操作


PY_PACKAGES_PATH="./packages/centos/pypackages"
RPM_PACKAGES_PATH="./packages/centos/rpms"
SSH_PRIVATE_KEY="/root/.ssh/id_rsa"  # deploy节点生成私钥存放的路径
SILENT=false  # 是否采用静默模式安装


# 传递参数
case $1 in
-h|--help)
    echo '-s | --silent    静默安装模式'
    echo '-h | --help      显示此帮助信息并退出'
    exit 0;
;;
-s|--silent)
	SILENT=true;
;;
esac


# 检测是否为root
root=$(id -u)
if [ "$root" -ne 0 ] ;then
    echo "[!]必须以root身份运行此脚本!"
    exit 1
fi


if [ $SILENT == false ] ;then
    echo "欢迎使用k8s离线安装脚本！"
    echo "安装前，请先确认你已经配置好当前目录下hosts文件中的各项。"
    echo "(若文件不存在，可由”./example/hosts.m-masters.example“文件复制得到)"
    read -p "检查无误后，请按回车键开始处理..."
else
    echo "脚本执行中..."
fi


# 安装python-pip
command -v pip >/dev/null
if [ $? == 0 ]; then
    echo "[-] pip 已存在，跳过安装..."
else
    echo -e "[+] 安装pip 中...\c"
    rpm -ivh "$RPM_PACKAGES_PATH/python-pip/*" --force --nodeps > /dev/null || { echo "pip安装失败"; exit 1; }
    echo "成功"
fi


# 安装ansible
command -v ansible >/dev/null
if [ $? == 0 ]; then
    echo "[-] ansible 已存在，跳过安装..."
else
    echo -e "[+] 安装ansible 中...\c"
    pip install --find-links $PY_PACKAGES_PATH ansible --disable-pip-version-check >/dev/null || { echo "失败"; exit 1; }
    echo "成功"
fi


# 配置SSH免密码登录
echo "[-]正在配置节点SSH免密登录..."
# 1.生成秘钥文件
if [ -f $SSH_PRIVATE_KEY ]; then

    if [ $SILENT == true ] ;then
        rewire="no"
    else
        read -p "[!]秘钥文件：$SSH_PRIVATE_KEY 已存在，是否覆盖？(yes/no)" rewire
    fi

    if [ $rewire == "yes" ]; then
        rm $SSH_PRIVATE_KEY
        echo -e "生成秘钥中...\c"
        ssh-keygen -t rsa -b 2048 -P '' -f $SSH_PRIVATE_KEY > /dev/null || { echo "失败"; exit 1; }
        echo "成功"
    else
        echo "将使用原始秘钥文件"
    fi    
else
    echo -e "生成秘钥中...\c"
    ssh-keygen -t rsa -b 2048 -P '' -f $SSH_PRIVATE_KEY > /dev/null || { echo "失败"; exit 1; }
    echo "成功"
fi

# 2.拷贝秘钥到各主机
    # 从配置文件hosts中提取各主机IP (提取+去重)
    host_ips=($(cat hosts | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}*' -o | awk '! a[$0]++'))
    # 复制秘钥到各主机
    echo "[-]正在将秘钥拷贝到各节点..."

    for(( i=0;i<${#host_ips[@]};i++))
    do
        echo -e "拷贝到：${host_ips[i]}...\c"
        ssh-copy-id -o StrictHostKeyChecking=no ${host_ips[i]} > /dev/null || { echo "失败"; }
        echo "成功"
    done


# 复制资源文件到/etc/ansible文件夹
if [ -d "/etc/ansible" ]; then
    
    if [ $SILENT == true ]; then
        copy_or_not="yes"
    else
        read -p "检测到文件夹 /etc/snsible 已存在，是否拷贝安装所需的资源文件？(yes/no)" copy_or_not
    fi
    
    if [ $copy_or_not == "yes" ]; then
        echo -e "[-]正在将资源文件拷贝到 /etc/ansible 路径下...\c"
        cp -r $(cd `dirname $0`; pwd)/* /etc/ansible > /dev/null || { echo "失败"; exit 1; }
        echo "成功"
    fi
else
    echo -e "[-]正在将资源文件拷贝到 /etc/ansible 路径下...\c"
    mkdir "/etc/ansible"
    cp -r $(cd `dirname $0`; pwd)/* /etc/ansible > /dev/null || { echo "失败"; exit 1; }
    echo "成功"
fi

# 测试SSH连接
echo "[-]预配置已经完成，正在测试与各节点的连接..."
ansible -m ping all || { echo "存在连接失败的节点，安装不能继续。请检查输出。"; exit 1; }


#################
# 开始安装
echo "[-]安装中..."

cd /etc/ansible
ansible-playbook 90.setup.yml


# TODO: ssh-copy-id时需要输入密码的问题(可能需要配置文件)
