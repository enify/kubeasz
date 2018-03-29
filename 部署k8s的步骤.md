## 部署k8s的步骤

### 目录
  - [注意事项](#注意事项)
  - [安装步骤](#安装步骤)
    - [准备必要的仓库与镜像](#准备必要的仓库与镜像)
    - [上传资源并修改配置文件](#上传资源并修改配置文件)
    - [开始部署](#开始部署)
  - [常用插件的部署](#常用插件的部署)
    - [Kube-DNS](#kube-dns)
    - [DashBoard](#dashboard)
    - [Heapster](#heapster)
    - [EFK](#efk)
    - [Ingress](#ingress)
    - [Ceph](#ceph)
  - [其它](#其它)
    - [常用命令](#常用命令)
    - [CentOS离线安装软件包的方法](#centos离线安装软件包的方法)
    - [参考文档](#有关k8s的更多命令使用方法及文档可参考)



### 注意事项
- 适用于CentOS7 .
- 组件版本：
  - kubernetes	v1.9.3
  - etcd		v3.3.1
  - docker	1.12.6
  - calico/node	v3.0.3
  - flannel	v0.10.0

### 安装步骤
- #### 准备必要的仓库与镜像
  - 在k8s的整体结构中，有一些组件是由docker镜像构成的（如网络组件flannel，基础组件pause）。它们在安装过程中，默认会本地或者公共仓库拉取。所以，在没有网络的内网环境下，事先搭建一个私有docker仓库是很有必要的。
    - ##### 搭建docker私有仓库的步骤如下：
      1. 选定一台服务器作为部署私有仓库的主机。
      2. 上传文件 `docker.tar.gz` 到该主机中，使用命令： `tar -xzvf docker-tar.gz` 解压，得到一个名为 `docker` 的文件夹。
      3. 使用命令： `rpm -ivh docker/*.rpm` 安装该文件夹中的rpm包，即完成了对 docker 的安装。
      4. 上传 `images` 文件夹下的 `registry-2.tar` 文件到该主机中，此文件为搭建私有仓库所需的镜像。
      5. 使用命令： `docker load < registry-2.tar` 加载这个tar为一个镜像。
      6. 这时，使用命令： `docker images` 查看镜像，你会发现 `registry` 镜像已经加载进去了，它的TAG为2 。
      7. 使用命令： `docker run -d -p 对外提供服务的端口:5000 --restart=always registry:2` 来启动一个容器（注意端口不要冲突）。
      8. 这时，在在浏览器中输入：`http://<该主机IP>:<上面指定的端口>/v2/_catalog` ，便可看到私有仓库服务已经运行了。
    - ##### 上传安装k8s所需的镜像
      - 访问上述的http地址，你会发现在 repositories 列表中现在并没有镜像，这个结果是正常的，因为你还没有开始 push 镜像到该仓库。
      - 出于安全考虑，仓库默认只允许https推送/拉取。为了防止在推送过程中报错，需要在本机的 `/etc/doker/daemon.json` 文件中加入一行，以开启本机到私有仓库的http推送/拉取功能：
      ```
      {"insecure-registries" : [ "<仓库IP>:<端口>" ]}
      ```
      - 重启本机上的 docker 服务： `systemctl restart docker`
      - 如果上述步骤无误的话，就可以开始推送镜像了。首先，需要将必要的镜像 load 到本机： 
      ```
      ➜ docker load < /path/to/images/flannel-v0.10.0-amd64.tar
      ➜ docker load < /path/to/images/pause-amd64-3.0.tar
      ```
      - load完成后，输入命令：`docker images` ，你会看到类似以下的结果：
      ```
      REPOSITORY                           TAG
      jmgao1983/flannel                    v0.10.0-amd64
      mirrorgooglecontainers/pause-amd64   3.0
      ```
      - 接下来，为这两个镜像打上tag:
      ```
      ➜ docker tag jmgao1983/flannel:v0.10.0-amd64  <私有仓库IP>:<端口>/<自定义前缀>/flannel:v0.10.0-amd64

      ➜ docker tag mirrorgooglecontainers/pause-amd64:3.0  <私有仓库IP>:<端口>/<自定义前缀>/pause-amd64:3.0
      ```
      - 再次运行命令： `docker images` 你会发现镜像列表中多了两个条目（自定义前缀以k8s为例）：
      ```
      REPOSITORY                           TAG
      <私有仓库IP>:<端口>/k8s/flannel       v0.10.0-amd64
      jmgao1983/flannel                    v0.10.0-amd64
      <私有仓库IP>:<端口>/k8s/pause-amd64   3.0
      mirrorgooglecontainers/pause-amd64   3.0
      ```
      - 使用以下命令将它们推送到私有仓库：
      ```
      ➜ docker push <私有仓库IP>:<端口>/<自定义前缀>/flannel:v0.10.0-amd64

      ➜ docker push <私有仓库IP>:<端口>/<自定义前缀>/pause-amd64:3.0
      ```
      - 此后，在浏览器中再次进入网址：`http://<私有仓库IP>:<端口>/v2/_catalog` ，可以看到镜像已经可见了：
      ```
      {
        "repositories": [
          "k8s/flannel",
          "k8s/pause-amd64"
        ]
      }
      ```

- #### 上传资源并修改配置文件
  - 选定任意一台主机作为部署节点，上传文件夹： `kube-offline` 到该主机：
  ```
  ➜ scp -r /path/to/kube-offline root@<部署节点IP>:/root
  ```
  - SSH登录到该主机，进入 `kube-offline` 文件夹，依据具体需求配置该目录下名为 `hosts` 的文件（若有特殊需求，可将目录：`/path/to/kube-offline/examples/` 下相应的配置样例复制为 hosts 文件，进行修改。其中：`hosts.allinone.example`为单节点的配置样例， `hosts.s-master.example` 为单主多节点的配置样例，`hosts.m-masters.example`为多主多节点的配置样例）。以多主多节点的配置文件为例，其中一些条目你可能需要注意：
    - [deploy] : 部署节点的IP。
    - [etcd] : Etcd节点的信息。节点数量需为单数。
    - [kube-master] : 主节点的信息。
    - [lb] : 负载均衡节点的信息。注意， `LB_IF` 项需要根据该主机的实际网卡情况配置。`LB_ROLE` 项应为 单 master 多 backup 。
    - [lb:vars] :负载均衡的一些参数，根据实际实际情况修改。同时留意同步修改文件： `/path/to/kube-offline/roles/lb/templates/haproxy.cfg.j2` 中的条目。
    - [kube-node] : 工作节点的信息。
    - MASTER_IP : 负载均衡虚拟IP的地址。
    - KUBE_APISERVER : K8S API Server的地址，根据 MASTER_IP 来修改即可。
    - CLUSTER_NETWORK : 集群网络插件，如无特殊要求，保持： "flannel" 即可。
    - ETCD_NODES : Etcd集群间通信的相关配置。根据实际Etcd节点信息来设置。
    - ETCD_ENDPOINTS : Etcd集群服务地址列表。根据实际Etcd节点信息来设置。
    - BASIC_AUTH_USER : K8S API Server 基本认证所使用的用户名。
    - BASIC_AUTH_PASS : K8S API Server基本认证所使用的密码。
    - docker_url : 私有仓库的地址。
    - docker_repo : k8s部署时所需镜像所在地址。(如私有库中为：/k8s/pause ,  /k8s/flannel ... ，则这项的值为：<私有仓库IP>:<端口>/k8s ，注意：所有插件镜像推送时都应使用这个前缀)。

- #### 开始部署
  - 在部署节点中执行 `/path/to/kube-offline/` 下的 `preset.sh` 文件，便可开始自动安装：
  ```
  ➜ ./preset.sh
  ```
  - 根据实际情况，脚本会依次询问各节点SSH密码，秘钥等相关信息，照着流程往下走即可。如无错误，则可完成k8s主体部分的安装。
  - 安装完成后，SSH登录到某个主节点，使用以下命令查询k8s的安装情况：
  ```
  ➜ kubectl get nodes  // 获取节点的相关信息
  ➜ kubectl get componentstatus  // 获取各组件的健康状态
  ```
  - 若安装过程中出错，需要对集群进行清理的话，请在部署节点执行：
  ```
  ➜ ansible-playbook /path/to/kube-offline/99.clean.yml
  ```

### 常用插件的部署
  - ##### Kube-DNS
    - Kube-DNS为集群内部提供域名解析服务，是安装完k8s之后首先需要部署的一个插件。它的部署方法如下：
      - 上传所需的镜像到私有仓库
        - kube-dns的部署需要三个镜像：`k8s-dns-kube-dns-amd64:1.14.8 `， `k8s-dns-dnsmasq-nanny-amd64:1.14.8`， `k8s-dns-sidecar-amd64:1.14.8` 。参考前面推送 pause, flannel 的方法来推送它们到私有仓库：
        ```
        // 加载镜像
        ➜ docker load < /path/to/images/k8s-dns-kube-dns-amd64-v1.14.8.tar
        ➜ docker load < /path/to/images/k8s-dns-dnsmasq-nanny-amd64-v1.14.8.tar
        ➜ docker load < /path/to/images/k8s-dns-sidecar-amd64-v1.14.8.tar

        // 打tag (自定义前缀以k8s为例，需与前面的相同)
        ➜ docker tag mirrorgooglecontainers/k8s-dns-kube-dns-amd64:1.14.8 <私有仓库IP>:<端口>/k8s/k8s-dns-kube-dns-amd64:1.14.8
        ➜ docker tag mirrorgooglecontainers/k8s-dns-dnsmasq-nanny-amd64:1.14.8 <私有仓库IP>:<端口>/k8s/k8s-dns-dnsmasq-nanny-amd64:1.14.8
        ➜ docker tag mirrorgooglecontainers/k8s-dns-sidecar-amd64:1.14.8 <私有仓库IP>:<端口>/k8s/k8s-dns-sidecar-amd64:1.14.8

        // 推送
        ➜ docker push <私有仓库IP>:<端口>/k8s/k8s-dns-kube-dns-amd64:1.14.8
        ➜ docker push <私有仓库IP>:<端口>/k8s/k8s-dns-dnsmasq-nanny-amd64:1.14.8
        ➜ docker push <私有仓库IP>:<端口>/k8s/k8s-dns-sidecar-amd64:1.14.8
        ```
      - 执行部署
        - SSH到部署节点，复制文件：`/etc/ansible/manifests/kubedns/kubedns.yaml` 到某个主节点主机：
        ```
        ➜ scp /etc/ansible/manifests/kubedns/kubedns.yaml root@<某主节点IP>:/root/
        ```
        - SSH到该主节点，使用以下命令来部署Kube-DNS：
        ```
        ➜ kubectl create -f /root/kubedns.yaml
        ```
      - 测试
        - 查看运行状态
        ```
        ➜ kubectl get pod -n kube-system | grep kube-dns
        ```
        - 查看服务
        ```
        ➜ kubectl get svc -n kube-system | grep kube-dns
        ```
        - 实际解析测试测试
          - 请参考文档：`/path/to/kube-offline/docs/guide/kube-dns.md` 进行测试。
  - ##### DashBoard
    - Kubernetes DashBoard是k8s的原生web界面，提供信息展示，资源管理等诸多功能。
      - 上传所需的镜像到私有仓库
        - dashboard 的部署需要一个镜像：`kubernetes-dashboard-amd64:v1.8.3` 。参照片前面部署 kube-dns 时的步骤来推送它：
        ```
        // 加载镜像
        ➜ docker load < /path/to/images/kubernetes-dashboard-amd64-v1.8.3.tar

        // 打tag (自定义前缀以k8s为例，需与前面的相同)
        ➜ docker tag mirrorgooglecontainers/kubernetes-dashboard-amd64:v1.8.3 <私有仓库IP>:<端口>/k8s/kubernetes-dashboard-amd64:v1.8.3
        
        // 推送
        ➜ docker push <私有仓库IP>:<端口>/k8s/kubernetes-dashboard-amd64:v1.8.3
        ```
      - 执行部署
        - SSH到部署节点，复制文件夹：`/etc/ansible/manifests/dashboard` 到某个主节点主机：
        ```
        ➜ scp -r /etc/ansible/manifests/dashboard root@<某主节点IP>:/root/
        ```
        - SSH到该主节点，使用以下命令来部署DashBoard：
        ```
        ➜ kubectl create -f /root/dashboard/kubernetes-dashboard.yaml
        ```
        - 使用以下命令来部署基本密码认证(密码文件位于主节点 `/etc/kubernetes/ssl/basic-auth.csv` )：
        ```
        ➜ kubectl create -f /root/dashboard/ui-admin-rbac.yaml
        ```
        - 使用以下命令来设置 default 角色的权限：
        ```
        ➜ kubectl create -f /root/dashboard/set_default_rbac.yaml
        ```
      - 测试
        - 查看运行状态
        ```
        ➜ kubectl get pod -n kube-system | grep kubernetes-dashboard
        ```
        - 查看服务
        ```
        ➜ kubectl get svc -n kube-system | grep kubernetes-dashboard
        ```
        - 查看集群服务地址
        ```
        ➜ kubectl cluster-info
        ```
        - 访问web界面
          - DashBoard的认证分为两步：一、K8S API Server的HTTP Basic Auth 。二、DashBoard自带的登录验证。
          - 使用命令：`kubectl cluster-info` 查询得到Dashboard服务的地址，复制到浏览器中打开它。
          - 暂时先忽略证书错误，而后会出现K8S API Server的基本认证。用户名和密码在部署时的 hosts 文件中已配置。
          - 第一步认证通过后，就可以看见DashBoard自带的认证界面。以令牌认证为例，获取token的方式如下：
            - SSH登录到某个主节点主机，使用以下命令获取token：
            ```
            ➜ kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep admin-user | awk '{print $1}')
            // 复制结果中 Name 以 "default-token" 开头的的那个条目的token
            ```
          - 填入 token 后点击登录即可，注意保存token到文件以备份。
        - 其它认证方式
          - 请参考文档：`/path/to/kube-offline/docs/guide/dashboard.md` 来配置。
      - 注意
        - 由于还未部署 Heapster 插件，当前 dashboard 不能展示 Pod、Nodes 的 CPU、内存等 metric 图形，后续部署 heapster后自然能够看到。
  - ##### Heapster
    - Heapster是一个集群性能监控工具。而 InfluxDB 则是一个时序数据库，可作为 Heapster 的数据存储后端。在安装了这两者之后，便可在DashBoard上显示更多有关资源和性能的信息。(当然，你也可以安装额外的可视化图表工具：`Grafana` 来对收集的数据进行更详尽的可视化)。
      - 上传所需的镜像到私有仓库
        - 完整的 Heapster + InfluxDB + Grafana 栈需要三个镜像：`heapster-amd64:v1.5.1`，`heapster-influxdb-amd64:v1.3.3`，`heapster-grafana-amd64:v4.4.3` 。请参考上面安装 dashboard 的步骤推送这三个镜像到私有仓库，这里不再详细说明。
      - 执行部署
        - SSH到部署节点，复制文件夹：`/etc/ansible/manifests/heapster` 到某个主节点主机：
        ```
        ➜ scp -r /etc/ansible/manifests/heapster root@<某主节点IP>:/root/
        ```
        - SSH到该主节点，使用以下命令来部署Heapster：
        ```
        ➜ kubectl create -f /root/heapster/heapster.yaml
        ```
        - 使用以下命令来部署Influxdb：
        ```
        ➜ kubectl create -f /root/heapster/influxdb.yaml
        ```
        - 使用以下命令来部署Grafana (可选，默认采用apiserver proxy方式访问，如需定制请参考文档：`/path/to/kube-offline/docs/guide/heapster.md` )：
        ```
        ➜ kubectl create -f /root/heapster/grafana.yaml
        ```
      - 测试
        - 查看运行状态
        ```
        ➜ kubectl get pods -n kube-system | grep -E 'heapster|monitoring'
        ```
        - 查看集群服务地址
        ```
        ➜ kubectl cluster-info
        ```
        - 访问web页面
          - 在浏览器中重新进入DashBoard，你会发现CPU, 内存，负载等信息已经可以显示了。
          - 访问由：`kubectl cluster-info` 命令查询得到的Grafana服务的地址，使用部署时的 hosts 文件中设置的账户密码进行认证。点击页面上的 Home > Cluster ，即可看见监控图形。
  - ##### EFK
    - EFK 是指由 Elasticsearch， Fluentd， Kibana 构建的一个日志搜集方案。其中 Fluentd 负责日志搜集，Elasticsearch 负责日志搜寻，Kibana 负责可视化。
      - 上传所需镜像到私有仓库
        - 完整的 Elasticsearch + Fluentd + Kibana 栈需要四个镜像：`elasticsearch:v5.6.4`，`alpine:3.6`，`fluentd-elasticsearch:v2.0.2`，`kibana:5.6.4` 。请参考上面安装 dashboard 的步骤推送这四个镜像到私有仓库，这里不再详细说明。
      - 执行部署
        - SSH到部署节点，复制文件夹：/etc/ansible/manifests/efk 到某个主节点主机：
        ```
        ➜ scp -r /etc/ansible/manifests/efk root@<某主节点IP>:/root/
        ```
        - SSH到该主节点，使用以下命令来部署EFK：
        ```
        ➜ kubectl create -f /root/efk/
        ```
      - 配置需要收集日志的节点
        - Fluentd 只会调度到有`beta.kubernetes.io/fluentd-ds-ready=true` 标签的节点，所以需要对收集日志的节点逐个打上标签：
        ```
        ➜ kubectl label nodes 192.168.1.1 beta.kubernetes.io/fluentd-ds-ready=true
        ➜ kubectl label nodes 192.168.1.2 beta.kubernetes.io/fluentd-ds-ready=true
        ➜ kubectl label nodes 192.168.1.3 beta.kubernetes.io/fluentd-ds-ready=true

        // 上面的配置将使Fluentd收集192.168.1.1, 192.168.1.2, 192.168.1.3 这三台主机的日志。
        ```
      - 测试
        - 查看运行状态
        ```
        ➜ kubectl get pods -n kube-system | grep -E 'elasticsearch|fluentd|kibana'
        ```
        - 查看服务
        ```
        ➜ get svc --all-namespaces | grep -E 'elasticsearch|kibana'
        ```
        - 查看集群服务地址
        ```
        ➜ kubectl cluster-info
        ```
        - 访问web界面
          - 访问由：`kubectl cluster-info` 命令查询得到的 Kibana 服务的地址，使用部署时的 hosts 文件中设置的账户密码进行认证。之后便可看到 Kibana 界面。
  - ##### Ingress
    - 注：请根据实际需求安装此插件，非必须安装。
    - Ingress是除 hostport，nodeport，clusterIP 以及 云环境专有的负载均衡器 外的访问集群内服务的方式，是一个允许入站连接到达群集服务的规则集合。（要详细了解请参考文档：`/path/to/kube-offline/docs/guide/ingress.md`）
      - 上传所需镜像到私有仓库
        - Ingress 的安装依赖于一个镜像：`traefik:latest` ，请参照上面安装 dashboard 的步骤推送这个镜像到私有仓库，这里不再详细说明。
      - 执行部署
        - SSH到部署节点，复制文件夹：/etc/ansible/manifests/ingress 到某个主节点主机：
        ```
        ➜ scp -r /etc/ansible/manifests/ingress root@<某主节点IP>:/root/
        ```
        - SSH到该主节点，使用以下命令来部署Ingress：
        ```
        ➜ kubectl create -f /root/ingress/traefik-ingress.yaml
        ```
      - 测试
        - 测试的方法略有复杂，请参考文档：`/path/to/kube-offline/docs/guide/ingress.md` 来进行测试。

  - #### Ceph
    - Ceph是一个分布式的文件系统，在K8S中可作为数据存储后端使用。
    - 有关Ceph的原理与组件构成，可参考这篇文章进行理解：[使用Ceph RBD为Kubernetes集群提供存储卷](https://tonybai.com/2016/11/07/integrate-kubernetes-with-ceph-rbd/)
      - ##### 节点分配
        - 在节点数量小于等于3的情况下，建议将每个节点都部署成 *监控节点* 和 *存储节点*。
        - 在节点数量大于3的情况下，建议选其中三个节点部署成 *监控节点* ，其余节点只部署成 *存储节点*。
        - 以下面的配置为例，我们来讲述一下部署过程：
        ```
        Node              HostNmae        Role
        192.168.1.1        ceph01         deploy, admin, mon, osd
        192.168.1.2        ceph02         mon, osd
        192.168.1.3        ceph03         mon, osd
        192.168.1.4        ceph04         osd
        
        // 注：由于ceph-deploy的运作依赖于主机名，所以请先确保主机名不重复。可通过 /etc/hostname 文件来修改。
        ```
      - ##### 关闭防火墙
        - 部署前需要关闭每个节点的防火墙：
        ```
        ➜ systemctl  stop firewalld
        ➜ systemctl  disable firewalld 
        ```
      - ##### 配置hosts文件
        - 编辑每个Ceph节点上的 `/etc/hosts` 文件，在其中加入每个节点IP到主机名的解析规则：
        ```
        ...
        192.168.1.1   ceph01
        192.168.1.2   ceph02
        192.168.1.3   ceph03
        192.168.1.4   ceph04
        ...
        ```
      - ##### 配置SSH免密登录
        - 请在deploy节点配置它到其它节点的免密登录：
          1. 使用以下命令生成秘钥：
          ```
          ➜ ssh-keygen -t rsa -b 2048 -P '' -f /root/.ssh/id_rsa
          ```
          2. 创建认证文件：
          ```
          ➜ cat /root/.ssh/id_rsa.pub > /root/.ssh/authorized_keys
          ```
          3. 创建认证配置文件：
          ```
           ➜ echo "Host *\n  StrictHostKeyChecking no\n  UserKnownHostsFile=/dev/null" > /root/.ssh/config
          ```
          4. 将目录复制到其它各个Ceph节点：
          ```
          ➜ scp -r /root/.ssh 192.168.1.XXX:/root/
          ```
      - ##### 前期准备
          - 安装ceph
            - 要部署Ceph集群，首先需要在每个节点都安装Ceph:
              - 复制 ceph 的rpm包到每个节点：
              ```
              ➜ scp -r /path/to/kube-offline/packages/centos/rpms/ceph root@<节点IP>:/root/
              ```
              - SSH到该主机，执行安装：
              ```
              ➜ rpm -ivh /root/ceph/*.rpm  --force --nodeps
          - 配置NTP
            - Ceph集群对时间同步的要求比较高，所以在内网时，自己配置一台NTP服务器是个比较好的选择。
              - 复制 ntp 的rpm包到每个节点：
              ```
              ➜ scp -r /path/to/kube-offline/packages/centos/rpms/ntp root@<节点IP>:/root/
              ```
              - SSH到该主机，执行安装：
              ```
              ➜ rpm -ivh /root/ntp/*.rpm
              ```
              - 选定一台主机作为NTP服务器，执行以下操作：
                - 编辑主机上的文件：`/etc/ntp.conf` ：
                ```
                # 注释掉以下几行：
                #server 0.centos.pool.ntp.org iburst
                #server 1.centos.pool.ntp.org iburst
                #server 2.centos.pool.ntp.org iburst
                #server 3.centos.pool.ntp.org iburst

                # 添加以下几行：
                server 127.127.1.0
                fudge 127.127.1.0 stratum 5
                disable auth
                Broadcastclient
                ```
                - 重启NTP服务，让修改生效：
                ```
                ➜ systemctl restart ntpd
                ```
              - 配置其它节点从这台主机同步时间：
                - 编辑上主机的文件：`/etc/ntp.conf` ：
                ```
                # 注释掉以下几行：
                #server 0.centos.pool.ntp.org iburst
                #server 1.centos.pool.ntp.org iburst
                #server 2.centos.pool.ntp.org iburst
                #server 3.centos.pool.ntp.org iburst

                # 添加以下一行：
                server <NTP服务器的IP>
                ```
                - 重启NTP服务，让修改生效：
                ```
                ➜ systemctl restart ntpd
                ```
      - ##### 部署Ceph集群
        - 下面将使用ceph官方提供的部署工具：`ceph-deploy` 来部署Ceph集群。
          - 首先，我们在deploy节点安装 `ceph-deploy` :
            - 上传 ceph-deploy 的rpm包到 deploy节点：
            ```
            ➜ scp -r /path/to/kube-offline/packages/centos/rpms/ceph-deploy   root@192.168.1.1:/root/
            ```
            - SSH到部署节点，执行安装：
            ```
            ➜ rpm -ivh /root/ceph-deploy/*.rpm  --force --nodeps
            ```
          - 在deploy节点创建配置文件保存目录，并进入：
          ```
          ➜ mkdir /root/ceph_config
          ➜ cd /root/ceph_config
          ```
          - 使用以下命令来开始部署Ceph集群，它的参数为监控节点的主机名，执行成功后将在当前目录生成配置文件：
          ```
          ➜ ceph-deploy new ceph01 ceph02 ceph03
          ```
          - 编辑：`/root/ceph_config` 目录下生成的 `ceph.conf` 文件，添加以下几行：
          ```
          osd pool default size = 2
          osd pool default min size = 1
          public network = 192.168.1.0/24
          mon_clock_drift_allowed = 5
          mon_clock_drift_warn_backoff = 30

          # 注：
          # 前两行配置表示设置数据备份数为2 。
          # public network 代表集群网络的网段，需根据实际情况修改。
          # 后面两行是设置集群可接受的时差。
          ```
          - 使用一下命令来初始化 *监控节点* 。执行完成后，将在目录下生成许多 `.keyring` 文件：
          ```
          ➜ ceph-deploy mon create-initial
          ```
          - 使用以下命令来将各 `.keyring` 文件同步到各个Node上，以便可以在各个Node上使用ceph命令连接到monitor：
          ```
          ➜ ceph-deploy admin ceph01 ceph02 ceph03 ceph04
          ```
          - 部署 *存储节点* ：
          ```
          ➜ ceph-deploy osd create ceph01:sdb ceph02:sdb ceph03:sdb ceph04:sdb
          
          // 参数说明：ceph01:sdb 代表把 ceph01 节点上的 sdb 整块硬盘加入到存储集群。sdb硬盘在格式化后被加入。其中sdb也可以是某个硬盘分区，如sdb1。

          // 如果一个节点有多个硬盘要加入集群，可以重复，例如:
          ➜ ceph-deploy osd create ceph01:sdb ceph01:sdc ceph02:sdb ceph03:sdb

          // 也可以分多次来加入,如：
          ➜ ceph-deploy osd create ceph01:sdb ceph02:sdb
          ➜ ceph-deploy osd create ceph01:sdc ceph03:sdb
          ```
      - 测试
      ```
      ➜ ceph -s  //检查集群状态信息
      ➜ ceph df  //查看ceph存储空间
      ➜ ceph mon stat  //查看mon的状态信息
      ➜ ceph osd tree  //查看osd的目录树
      ```

### 其它
- #### 常用命令
  ```
  ➜ kubectl get nodes // 获取节点信息
  ➜ kubectl get componentstatus  // 获取集群组件的信息
  ➜ kubectl get pods  // 获取Pod信息(可使用参数--all-namespace 获取所有命名空间的信息)
  ➜ kubectl get deployments  // 获取Deployment信息(可使用参数--all-namespace 获取所有命名空间的信息
  ➜ kubectl get svc  // 获取Service信息(可使用参数--all-namespace 获取所有命名空间的信息
  ➜ kubectl cluster-info  // 获取集群服务信息
  ➜ kubectl describe <资源类型> <资源名>  // 获取资源的定义详情
  ➜ kubectl logs <pod名>  // 获取某个Pod的日志
  ➜ kubectl create -f <YAML文件>  // 根据文件来创建资源
  ➜ kubectl delete -f <YAML文件>  // 根据文件来删除已有资源
  ```

- #### CentOS离线安装软件包的方法
```
// 离线下载rpm包及其依赖
➜ yum install --downloadonly --downloaddir=<保存的目录>  <包名>

// 离线安装rpm包，并在当前目录下寻找并解决依赖问题
➜ rpm -ivh ./*.rpm
```

- #### 有关K8S的更多命令使用方法及文档可参考：
  - [Kubernetes中文社区](https://www.kubernetes.org.cn/docs)
  - [Kubernetes指南](https://github.com/feiskyer/kubernetes-handbook)
  - [使用Ansible脚本安装K8S集群](https://github.com/gjmzj/kubeasz)
