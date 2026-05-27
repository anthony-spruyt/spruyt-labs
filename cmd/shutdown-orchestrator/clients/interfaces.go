package clients

import "context"

// CNPGCluster represents a CNPG cluster with its hibernation state.
type CNPGCluster struct {
  Namespace  string
  Name       string
  Hibernated bool
}

// Node represents a Kubernetes node.
type Node struct {
  Name  string
  IP    string
  Ready bool
}

// PodInfo represents metadata about a Kubernetes pod.
type PodInfo struct {
  Namespace string
  Name      string
  NodeName  string
  DaemonSet bool // owned by a DaemonSet
  HasPVC    bool // has persistentVolumeClaim volumes
}

// KubeClient abstracts Kubernetes API operations.
type KubeClient interface {
  // CNPG operations
  GetCNPGClusters(ctx context.Context) ([]CNPGCluster, error)
  SetCNPGHibernation(ctx context.Context, ns, name string, hibernate bool) error

  // Ceph operations
  DeploymentExists(ctx context.Context, ns, name string) (bool, error)
  ExecInDeployment(ctx context.Context, ns, deploy string, cmd []string) (string, error)
  ScaleDeployment(ctx context.Context, ns, name string, replicas int32) error
  ListDeploymentNames(ctx context.Context, ns, labelSelector string) ([]string, error)
  GetDeploymentReplicas(ctx context.Context, ns, name string) (int32, error)

  // Node operations
  GetNodes(ctx context.Context) ([]Node, error)
  CordonNode(ctx context.Context, name string) error
  UncordonNode(ctx context.Context, name string) error
  GetPodsOnNode(ctx context.Context, nodeName string) ([]PodInfo, error)
  DeletePod(ctx context.Context, ns, name string, gracePeriodSeconds int64) error

  // Recovery detection
  IsCephNooutSet(ctx context.Context) (bool, error)
}

// TalosClient abstracts Talos node operations.
type TalosClient interface {
  Shutdown(ctx context.Context, nodeIP string, force bool) error
  // Ping verifies connectivity to a Talos node by requesting its version.
  Ping(ctx context.Context, nodeIP string) error
  // Close releases all cached gRPC connections.
  Close() error
}

// UPSClient abstracts UPS status queries.
type UPSClient interface {
  GetStatus(ctx context.Context) (string, error)
  // Close closes the persistent connection.
  Close() error
}
