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
  Ready bool
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

  // Node operations
  GetNodes(ctx context.Context) ([]Node, error)

  // Recovery detection
  IsCephNooutSet(ctx context.Context) (bool, error)
}

// TalosClient abstracts Talos node operations.
type TalosClient interface {
  Shutdown(ctx context.Context, nodeIP string, force bool) error
}

// UPSClient abstracts UPS status queries.
type UPSClient interface {
  GetStatus(ctx context.Context) (string, error)
}
