# Container Network 1
<!-- ---
title: Container Network 1
date: 2022-02-15 22:13:14
tags: [network]
--- -->

参考文章：[networking-4-docker-sigle-host](https://morven.life/posts/networking-4-docker-sigle-host/)

bridge 是 docker 默认的网络模型，bridge 网络模型解决了单宿主机上的容器之间的通信以及容器访问外部和对外暴露服务的问题。接下来尝试通过 linux 虚拟网络设备 + iptables + 路由表来模拟类似的功能。

### bridge 网络模拟

基本的网络拓扑图如下所示：：

![bridge](https://i.imgur.com/mU1pWyv.png)

1. 首先创建两个 netns 网络命名空间：

```bash
# ip netns add netns_A
# ip netns add netns_B
# ip netns
netns_B
netns_A
```

2. 在 default 网络命名空间中创建网桥设备 mybr0，并分配 IP 地址172.18.0.1/16使其成为对应子网的网关：

```bash
# ip link add name mybr0 type bridge
# ip addr add 172.18.0.1/16 dev mybr0
# ip link set mybr0 up
# ip link show mybr0
3: mybr0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000
    link/ether 1e:51:a0:ee:ad:98 brd ff:ff:ff:ff:ff:ff
# ip route
...
172.18.0.0/16 dev mybr0 proto kernel scope link src 172.18.0.1 
```

3. 接下来，创建 veth 设备对并连接在第一步创建的两个网络命名空间：

```bash
# ip link add vethA type veth peer name vethpA
# ip link show vethA
5: vethA@vethpA: <BROADCAST,MULTICAST,M-DOWN> mtu 1500 qdisc noop state DOWN mode DEFAULT group default qlen 1000
    link/ether be:c8:3d:b2:e4:85 brd ff:ff:ff:ff:ff:ff
# ip link show vethpA
13: vethpA@vethA: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN mode DEFAULT group default qlen 1000
    link/ether 86:d6:16:43:54:9e brd ff:ff:ff:ff:ff:ff
```

4. 将上一步创建的 veth 设备对的一端 vethA 连接到 mybr0 网桥并启动：

```bash
# ip link set dev vethA master mybr0
# ip link set vethA up
# bridge link
5: vethA@vethpA: <NO-CARRIER,BROADCAST,MULTICAST,UP,M-DOWN> mtu 1500 master mybr0 state disabled priority 32 cost 2 
```

5. 将 veth 设备对的另一端 vethpA 放到网络命名空间 netns_A 中并配置 IP 启动：

```bash
# ip link set vethpA netns netns_A
# ip netns exec netns_A ip link set vethpA name eth0
# ip netns exec netns_A ip addr add 172.18.0.2/16 dev eth0
# ip netns exec netns_A ip link set eth0 up
# ip netns exec netns_A ip addr show type veth
4: eth0@if5: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether 42:a2:e6:be:e1:00 brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 172.18.0.2/16 scope global eth0
       valid_lft forever preferred_lft forever
    inet6 fe80::40a2:e6ff:febe:e100/64 scope link 
       valid_lft forever preferred_lft forever
```

6. 现在就可以验证从 netns_A 网络命名空间中访问 mybr0 网关：

```bash
# ip netns exec netns_A ping -c 2 172.18.0.1
PING 172.18.0.1 (172.18.0.1) 56(84) bytes of data.
64 bytes from 172.18.0.1: icmp_seq=1 ttl=64 time=0.089 ms
64 bytes from 172.18.0.1: icmp_seq=2 ttl=64 time=0.064 ms

--- 172.18.0.1 ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1024ms
rtt min/avg/max/mdev = 0.064/0.076/0.089/0.012 ms
```

7. 接下来，按照上述步骤创建连接 default 和 netns_B 网络命名空间 veth 设备对：

```bash
# ip netns exec netns_A ip route add default via 172.18.0.1
# ip netns exec netns_A ip route
default via 172.18.0.1 dev eth0 
172.18.0.0/16 dev eth0 proto kernel scope link src 172.18.0.2 
```

8. 接下来，按照上述步骤创建连接 default 和 netns_B 网络命名空间 veth 设备对：

```bash
# ip link add vethB type veth peer name vethpB
# ip link set dev vethB master mybr0
# ip link set vethB up
# ip link set vethpB netns netns_B
# ip netns exec netns_B ip link set vethpB name eth0
# ip netns exec netns_B ip addr add 172.18.0.3/16 dev eth0
# ip netns exec netns_B ip link set eth0 up
# ip netns exec netns_B ip route add default via 172.18.0.1
# ip netns exec netns_B ip add show eth0
6: eth0@if7: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether 4a:31:85:5e:39:6e brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 172.18.0.3/16 scope global eth0
       valid_lft forever preferred_lft forever
    inet6 fe80::4831:85ff:fe5e:396e/64 scope link 
       valid_lft forever preferred_lft forever
# ip netns exec netns_B ip route show
default via 172.18.0.1 dev eth0 
172.18.0.0/16 dev eth0 proto kernel scope link src 172.18.0.3 
```

9. 默认情况下 Linux 会把网桥设备 bridge 的转发功能禁用，所以在 netns_A 里面是 ping 不通 netns_B 的，需要额外增加一条 iptables 规则才能激活网桥设备 bridge 的转发功能：
(在我的测试过程中似乎并不需要这一步，系统 ubuntu 20.04)

```bash
# iptables -A FORWARD -i mybr0 -j ACCEPT
```

10. 现在就可以验证两个网络命名空间之间可以互通：

```bash
# ip netns exec netns_A ping -c 2 172.18.0.3
PING 172.18.0.3 (172.18.0.3) 56(84) bytes of data.
64 bytes from 172.18.0.3: icmp_seq=1 ttl=64 time=0.027 ms
64 bytes from 172.18.0.3: icmp_seq=2 ttl=64 time=0.054 ms

--- 172.18.0.3 ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1025ms
rtt min/avg/max/mdev = 0.027/0.040/0.054/0.013 ms

# ip netns exec netns_B ping -c 2 172.18.0.2
PING 172.18.0.2 (172.18.0.2) 56(84) bytes of data.
64 bytes from 172.18.0.2: icmp_seq=1 ttl=64 time=0.063 ms
64 bytes from 172.18.0.2: icmp_seq=2 ttl=64 time=0.070 ms

--- 172.18.0.2 ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1001ms
rtt min/avg/max/mdev = 0.063/0.066/0.070/0.003 ms
```

实际上，此时两个网络命名空间处于同一个子网中，所以网桥设备 mybr0 还是工作在二层（数据链路层），只需要对方的 MAC 地址就可以访问。

但是如果需要从两个网络命名空间访问其他网段的地址，这个时候网桥设备 mybr0 设置为默认网关地址就发挥作用了：来自于两个网络命名空间的数据包发现目标 IP 地址并不是本子网地址，于是发给网关 mybr0，此时网桥设备 mybr0 其实工作在三层（IP网络层），它收到数据包之后，查看本地路由与目标 IP 地址，寻找下一跳的地址

### iptables

这时候从 netns 网络命名空间中还无法访问到公网地址，首先由于系统默认不进行 IP forwarding，mybr0 的数据包没有通过 ens3 发从出去。首先要打开 IP forwarding 开关，之后由于发出的 ICMP 包没有做 SNAT，返回的 IP 包无法回到对应子网内。这时候通过 iptables 配置 SNAT 来解决这个问题。

```bash
# echo 1 > /proc/sys/net/ipv4/ip_forward
# iptables -t nat -A POSTROUTING -s 172.18.0.0/16  -o ens3 -j MASQUERADE
# iptables -t nat -L -n -v
Chain PREROUTING (policy ACCEPT 367 packets, 61770 bytes)
 pkts bytes target     prot opt in     out     source               destination         

Chain INPUT (policy ACCEPT 366 packets, 61686 bytes)
 pkts bytes target     prot opt in     out     source               destination         

Chain OUTPUT (policy ACCEPT 78 packets, 5838 bytes)
 pkts bytes target     prot opt in     out     source               destination         

Chain POSTROUTING (policy ACCEPT 78 packets, 5838 bytes)
 pkts bytes target     prot opt in     out     source               destination         
    1    84 MASQUERADE  all  --  *      ens3    172.18.0.0/16        0.0.0.0/0

# ip netns exec netns_A ping -c 2 220.181.38.251
PING 220.181.38.251 (220.181.38.251) 56(84) bytes of data.
64 bytes from 220.181.38.251: icmp_seq=1 ttl=50 time=37.9 ms
64 bytes from 220.181.38.251: icmp_seq=2 ttl=50 time=37.7 ms

--- 220.181.38.251 ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1001ms
rtt min/avg/max/mdev = 37.668/37.785/37.902/0.117 ms
```
