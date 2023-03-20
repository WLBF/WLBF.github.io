# Kubernetes Device Plugin
<!-- ---
title: Kubernetes Device Plugin
tags: k8s
date: 2022-01-17 22:09:20
--- -->

k8s 的 devcie plugin framework 给了开发者自己实现 device plugin 来向 k8s 集群中声明自定义硬件资源的能力。device plugin 实现上是一个 grpc server，device plugin 首先会向 kubelet 注册自己， 之后kubelet 会调用 device plugin 的 grpc 函数来获取需要的硬件信息。一个简单的 device plugn 例子： [github.com/WLBF/null-device-plugin](https://github.com/WLBF/null-device-plugin)

## grpc 接口

```protobuf
service Registration {
      rpc Register(RegisterRequest) returns (Empty) {}
}
```

```protobuf
service DevicePlugin {
      // GetDevicePluginOptions returns options to be communicated with Device Manager.
      rpc GetDevicePluginOptions(Empty) returns (DevicePluginOptions) {}

      // ListAndWatch returns a stream of List of Devices
      // Whenever a Device state change or a Device disappears, ListAndWatch
      // returns the new list
      rpc ListAndWatch(Empty) returns (stream ListAndWatchResponse) {}

      // Allocate is called during container creation so that the Device
      // Plugin can run device specific operations and instruct Kubelet
      // of the steps to make the Device available in the container
      rpc Allocate(AllocateRequest) returns (AllocateResponse) {}

      // GetPreferredAllocation returns a preferred set of devices to allocate
      // from a list of available ones. The resulting preferred allocation is not
      // guaranteed to be the allocation ultimately performed by the
      // devicemanager. It is only designed to help the devicemanager make a more
      // informed allocation decision when possible.
      rpc GetPreferredAllocation(PreferredAllocationRequest) returns (PreferredAllocationResponse) {}

      // PreStartContainer is called, if indicated by Device Plugin during registeration phase,
      // before each container start. Device plugin can run device specific operations
      // such as resetting the device before making devices available to the container.
      rpc PreStartContainer(PreStartContainerRequest) returns (PreStartContainerResponse) {}
}
```

## 实现

### 注册

```golang
const (
	// Healthy means that the device is healthy
	Healthy = "Healthy"
	// Unhealthy means that the device is unhealthy
	Unhealthy = "Unhealthy"

	// Version means current version of the API supported by kubelet
	Version = "v1beta1"
	// DevicePluginPath is the folder the Device Plugin is expecting sockets to be on
	// Only privileged pods have access to this path
	// Note: Placeholder until we find a "standard path"
	DevicePluginPath = "/var/lib/kubelet/device-plugins/"
	// KubeletSocket is the path of the Kubelet registry socket
	KubeletSocket = DevicePluginPath + "kubelet.sock"

	// DevicePluginPathWindows Avoid failed to run Kubelet: bad socketPath,
	// must be an absolute path: /var/lib/kubelet/device-plugins/kubelet.sock
	// https://github.com/kubernetes/kubernetes/issues/93262
	// https://github.com/kubernetes/kubernetes/pull/93285#discussion_r458140701
	DevicePluginPathWindows = "\\var\\lib\\kubelet\\device-plugins\\"
	// KubeletSocketWindows is the path of the Kubelet registry socket on windows
	KubeletSocketWindows = DevicePluginPathWindows + "kubelet.sock"

	// KubeletPreStartContainerRPCTimeoutInSecs is the timeout duration in secs for PreStartContainer RPC
	// Timeout duration in secs for PreStartContainer RPC
	KubeletPreStartContainerRPCTimeoutInSecs = 30
)
```

device plugin 首先通过路径为 `/var/lib/kubelet/device-plugins/kubelet.sock` 的 unix socket 向 kubelet 注册自己。之后会在 `/var/lib/kubelet/device-plugins/` 目录下生成一个 unix socket 来提供 grpc 服务给 kubelet 调用，所以注册参数中包含了 unix socket 的名称。注册参数中的 `ResourceName` 就是向集群中注册的资源名称

```golang
// Register registers the device plugin for the given resourceName with Kubelet.
func (m *NullDevicePlugin) Register() error {
	conn, err := m.dial(pluginapi.KubeletSocket, 5*time.Second)
	if err != nil {
		return err
	}
	defer conn.Close()

	client := pluginapi.NewRegistrationClient(conn)
	reqt := &pluginapi.RegisterRequest{
		Version:      pluginapi.Version,
		Endpoint:     "example-null.sock",
		ResourceName: "example.com/null",
		Options: &pluginapi.DevicePluginOptions{
			GetPreferredAllocationAvailable: false,
			PreStartRequired:                false,
		},
	}

	_, err = client.Register(context.Background(), reqt)
	if err != nil {
		return err
	}
	return nil
}
```

`DevicePluginOptions` 标示了 kubelet 是否需要调用 `GetPreferredAllocation` 和 `PreStartContainer` 这两个可选接口。

```golang
type DevicePluginOptions struct {
	// Indicates if PreStartContainer call is required before each container start
	PreStartRequired bool `protobuf:"varint,1,opt,name=pre_start_required,json=preStartRequired,proto3" json:"pre_start_required,omitempty"`
	// Indicates if GetPreferredAllocation is implemented and available for calling
	GetPreferredAllocationAvailable bool     `protobuf:"varint,2,opt,name=get_preferred_allocation_available,json=getPreferredAllocationAvailable,proto3" json:"get_preferred_allocation_available,omitempty"`
}
```

### kubelet 重启

device plugin 还需要在 kubelet 重启时重新注册自己。kubelet 在重启时会将 `/var/lib/kubelet/device-plugins/` 下所有 unix socket 删除，device plugin 可以通过监测 unix socket 是否被删除来感知 kubelet 重启，继而重新注册。

### 设备列表

kubelet 一定会调用的两个接口是 `ListAndWatch` 和 `Allocate`，protobuf 中的注释已经解释的很清楚了, 比如下面 `ListAndWatch` 代码向 kubelet 注册了两个假的设备， 注意这里还上报了设备的健康状况，在真实场景下如果设备健康状况出现变化，还需要及时发送新设备列表给 kubelet。

```golang
// ListAndWatch lists devices and update that list according to the health status
func (m *NullDevicePlugin) ListAndWatch(e *pluginapi.Empty, s pluginapi.DevicePlugin_ListAndWatchServer) error {
	devices := []*pluginapi.Device{
		{
			ID:     "0e2da650-5f9f-4ba2-a42d-592ee5cd3616",
			Health: pluginapi.Healthy,
		},
		{
			ID:     "4516ceb8-cafa-45f3-9d93-147c1a9c072b",
			Health: pluginapi.Healthy,
		},
	}

	if err := s.Send(&pluginapi.ListAndWatchResponse{Devices: devices}); err != nil {
		return err
	}
	<-s.Context().Done()
	return nil
}
```

## 部署

在通过 daemonset 在测试集群中部署 device plugin 之后，describe node 可以观察到新注册的资源信息：

```text
$ kubectl describe no worker-0
...
Capacity:
  cpu:                2
  ephemeral-storage:  4901996Ki
  example.com/null:   2
  hugepages-1Gi:      0
  hugepages-2Mi:      0
  memory:             2030684Ki
  pods:               110
Allocatable:
  cpu:                2
  ephemeral-storage:  4517679507
  example.com/null:   2
  hugepages-1Gi:      0
  hugepages-2Mi:      0
  memory:             1928284Ki
  pods:               110
...
Allocated resources:
  (Total limits may be over 100 percent, i.e., overcommitted.)
  Resource           Requests   Limits
  --------           --------   ------
  cpu                100m (5%)  100m (5%)
  memory             50Mi (2%)  50Mi (2%)
  ephemeral-storage  0 (0%)     0 (0%)
  hugepages-1Gi      0 (0%)     0 (0%)
  hugepages-2Mi      0 (0%)     0 (0%)
  example.com/null   0          0

```
