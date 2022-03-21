1. Add file host on 3 nodes

172.16.44.191   node1
172.16.44.238   node2
172.16.44.247   node3

Lưu ý: hostname trùng với các tên host trên 
2. Install the RabbitMQ Server
- Add the EPEL repository to the CentOS 7 system.
yum -y install epel-release

- Install erlang 24.x
wget https://packages.erlang-solutions.com/erlang/rpm/centos/7/x86_64/esl-erlang_24.0.2-1~centos~7_amd64.rpm
yum -y install esl-erlang*.rpm
	+ Open the Erlang shell to verify the installation:
	erl
	
- Install RabbitMQ 3.9.8
wget https://github.com/rabbitmq/rabbitmq-server/releases/download/v3.9.8/rabbitmq-server-3.9.8-1.el7.noarch.rpm
rpm --import https://github.com/rabbitmq/signing-keys/releases/download/2.0/rabbitmq-release-signing-key.asc
yum install socat logrotate -y
yum install rabbitmq-server-3.9.8-1.el7.noarch.rpm -y

- Start application on all nodes
systemctl start rabbitmq-server.service
systemctl enable rabbitmq-server.service
rabbitmq-plugins enable rabbitmq_management

- Create network partition on all nodes
touch /etc/rabbitmq/rabbitmq.conf	
echo "cluster_partition_handling = pause_minority" > /etc/rabbitmq/rabbitmq.conf
systemctl restart rabbitmq-server.service

- Copy erlang cookie to config cluster
scp /var/lib/rabbitmq/.erlang.cookie root@node2:/var/lib/rabbitmq/
scp /var/lib/rabbitmq/.erlang.cookie root@node3:/var/lib/rabbitmq/

- Add firewall
firewall-cmd --zone=public --permanent --add-port=4369/tcp --add-port=25672/tcp --add-port=5671-5672/tcp --add-port=15672/tcp  --add-port=61613-61614/tcp --add-port=1883/tcp --add-port=8883/tcp
firewall-cmd --reload

- On slave node, run the following commands to join cluster:
rabbitmqctl stop_app
rabbitmqctl join_cluster rabbit@node1
rabbitmqctl start_app

- Check slave node joined cluster, run on master node
rabbitmqctl cluster_status

- Add user on master node
rabbitmqctl add_user admin 123456
rabbitmqctl set_user_tags admin administrator
rabbitmqctl set_permissions -p / admin ".*" ".*" ".*"
rabbitmqctl delete_user guest

- Run command on all nodes to verify user synchronized
rabbitmqctl list_users

- Config HA Policy for cluster
rabbitmqctl set_policy -p "/" --priority 1 --apply-to "all" ha ".*" '{ "ha-mode": "all", "ha-sync-mode": "automatic"}'

Explain:
	-p "/": Use this policy on the "/" vhost (the default after installation)
	--priority 1: The order in which to apply policies
	--apply-to "all": Can be "queues", "exchanges" or "all"
	ha: The name we give to our policy
	".*": The regular expression which is used to decide to which queues or exchanges this policy is applied. ".*" will match anything
	'{ "ha-mode": "all", "ha-sync-mode": "automatic"}': The JSON representation of the policy. This document describes that we want mirror the data to all the nodes in the cluster

- Run command on all nodes to verify ha policy synchronized
rabbitmqctl list_policies

- Login to UI RabbitMQ:
http://[ip_node1-3]:15672
Username: 
Password:


- Testing the setup
Chúng ta sẽ restart lần lượt từng node.

Giả sử tôi thực hiện restart theo thứ tự sau:
stop node 3 -> stop node 1 -> start node 3 -> start node 1. Node 2 vẫn giữ hoạt động để đảm bảo dịch vụ không down.

Stop node 3, node 1

Trên node 3:

[root@rabbit3 ~]#  rabbitmqctl stop
Stopping and halting node rabbit@rabbit3 ...
Bạn có thể dùng service rabbitmq-server stop thay cho rabbitmqctl top

Trên node 1:

[root@rabbit1 ~]# service rabbitmq-server stop
Stopping rabbitmq-server: rabbitmq-server.
Xem cluster status trên node 2:

[root@rabbit2 root]# rabbitmqctl cluster_status
Cluster status of node rabbit@rabbit2 ...
[{nodes,[{disc,[rabbit@rabbit1,rabbit@rabbit2,rabbit@rabbit3]}]},
 {running_nodes,[rabbit@rabbit2]},
 {cluster_name,<<"rabbit@rabbit2">>},
 {partitions,[]}]
Chỉ còn một mình node 2 đang hoạt động

Start node 3, node 1

Trên node 3:

[root@rabbit3 ~]# service rabbitmq-server start
Starting rabbitmq-server: SUCCESS
rabbitmq-server.
Trên node 1:

[root@rabbit1 ~]# service rabbitmq-server start
Starting rabbitmq-server: SUCCESS
rabbitmq-server.
Xem cluster status trên node 2:

[root@rabbit2 root]# rabbitmqctl cluster_status
Cluster status of node rabbit@rabbit2 ...
[{nodes,[{disc,[rabbit@rabbit1,rabbit@rabbit2,rabbit@rabbit3]}]},
 {running_nodes,[rabbit@rabbit1,rabbit@rabbit3,rabbit@rabbit2]},
 {cluster_name,<<"rabbit@rabbit2">>},
 {partitions,[]}]

Như vậy, ngay sau khi được start trở lại, các node sẽ tự động tham gia vào cluster và running luôn.

Trong các trường hợp có sự cố nghiêm trọng như toàn bộ các node đều down lần lượt hoặc tất cả đều down đồng thời thì quy trình start cluster lại hơi khác một chút. Chúng ta đi vào từng trường hợp một.

Trường hợp thứ nhất: Tình huống xảy ra khi bạn cần restart cluster để upgrade cho rabbitmq hoặc erlang. Sau khi node 1, node 2 được bạn stop thì thảm họa xảy ra với node còn lại. Node còn lại bị down ngoài ý muốn. Trong trường hợp này việc khởi động lại cluster đòi hỏi thứ tự: Node cuối cùng bị down phải là node đầu tiên được start. Giả sử các node bị down theo thứ tự: node 3 -> node 1 -> node 2. Sau đó tôi cố gắng start các node 3 hoặc node 1 đầu tiên. Tôi sẽ không thành công. Rabbitmq để lại vài dòng log sau:

This cluster node was shut down while other nodes were still running.
To avoid losing data, you should start the other nodes first, then
start this one. To force this node to start, first invoke
"rabbitmqctl force_boot". If you do so, any changes made on other
cluster nodes after this one was shut down may be lost.
Để khởi động được cluster, bạn chỉ cần tuân theo nguyên tắc, start node 2 đầu tiên. Với các node sau, thứ tự không quan trọng. Bạn có thể dùng thứ tự node 2 - > node 1 -> node 3 hoặc node2 -> node 3 -> node1.

Trường hợp thứ hai: Cũng giống trường hợp một nhưng đáng tiếc là node 2 bị sự cố quá nghiêm trọng không thể phục hồi được. Vậy là node cuối cùng không thể boot được. Lúc này bạn phải ép một node không phải node down cuối cùng làm node khởi điểm

[root@rabbit1 root]# rabbitmqctl force_boot
Forcing boot for Mnesia dir /var/lib/rabbitmq/mnesia/rabbit@rabbit1 ...
[root@rabbit1 root]# service rabbitmq-server start
Starting rabbitmq-server: SUCCESS
rabbitmq-server.
Sau đó bạn khởi động lại các node kế tiếp.

Trường hợp thứ ba: Khủng khiếp hơn ! Bạn chẳng làm gì nhưng cụm server mà chứa rabbitmq cluster bị crash đột ngột. Lúc này thì bạn chẳng thể biết node nào down trước hay down sau cả. Cách xử lý giống hệt trường hợp thứ hai


===========
Tạo Quorum Queue

Vào tab Queues để tạo queue, và trải nghiệm bật tắt các node. Để test việc Hight Avalibility của queue https://tungexplorer.s3.ap-southeast-1.amazonaws.com/rabbitmq/quorumadmin.JPG
Lưu ý: chọn bất kỳ 1 node để làm leader cho queue. (không quan trọng, sau này có sự cố tự động cluster sẽ bầu lại leader mới)
