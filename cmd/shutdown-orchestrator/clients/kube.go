package clients

import (
  "bytes"
  "context"
  "fmt"
  "strings"

  corev1 "k8s.io/api/core/v1"
  apierrors "k8s.io/apimachinery/pkg/api/errors"
  metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
  "k8s.io/apimachinery/pkg/runtime/schema"
  "k8s.io/apimachinery/pkg/types"
  "k8s.io/client-go/dynamic"
  "k8s.io/client-go/kubernetes"
  "k8s.io/client-go/kubernetes/scheme"
  "k8s.io/client-go/rest"
  "k8s.io/client-go/tools/remotecommand"
)

// RealKubeClient implements KubeClient using the real Kubernetes API.
type RealKubeClient struct {
  clientset     *kubernetes.Clientset
  dynamicClient dynamic.Interface
  restConfig    *rest.Config
}

// NewKubeClient creates a new Kubernetes client using in-cluster configuration.
func NewKubeClient() (*RealKubeClient, error) {
  config, err := rest.InClusterConfig()
  if err != nil {
    return nil, fmt.Errorf("building in-cluster config: %w", err)
  }

  clientset, err := kubernetes.NewForConfig(config)
  if err != nil {
    return nil, fmt.Errorf("creating kubernetes clientset: %w", err)
  }

  dynClient, err := dynamic.NewForConfig(config)
  if err != nil {
    return nil, fmt.Errorf("creating dynamic client: %w", err)
  }

  return &RealKubeClient{
    clientset:     clientset,
    dynamicClient: dynClient,
    restConfig:    config,
  }, nil
}

var cnpgClusterGVR = schema.GroupVersionResource{
  Group:    "postgresql.cnpg.io",
  Version:  "v1",
  Resource: "clusters",
}

// GetCNPGClusters lists all CNPG clusters across all namespaces and returns
// their hibernation state.
func (k *RealKubeClient) GetCNPGClusters(ctx context.Context) ([]CNPGCluster, error) {
  list, err := k.dynamicClient.Resource(cnpgClusterGVR).Namespace("").List(ctx, metav1.ListOptions{})
  if err != nil {
    return nil, fmt.Errorf("listing CNPG clusters: %w", err)
  }

  clusters := make([]CNPGCluster, 0, len(list.Items))
  for _, item := range list.Items {
    annotations := item.GetAnnotations()
    hibernated := annotations["cnpg.io/hibernation"] == "on"

    clusters = append(clusters, CNPGCluster{
      Namespace:  item.GetNamespace(),
      Name:       item.GetName(),
      Hibernated: hibernated,
    })
  }

  return clusters, nil
}

// SetCNPGHibernation sets or removes the hibernation annotation on a CNPG cluster.
func (k *RealKubeClient) SetCNPGHibernation(ctx context.Context, ns, name string, hibernate bool) error {
  var patch string
  if hibernate {
    patch = `{"metadata":{"annotations":{"cnpg.io/hibernation":"on"}}}`
  } else {
    patch = `{"metadata":{"annotations":{"cnpg.io/hibernation":null}}}`
  }

  _, err := k.dynamicClient.Resource(cnpgClusterGVR).Namespace(ns).Patch(
    ctx, name, types.MergePatchType, []byte(patch), metav1.PatchOptions{},
  )
  if err != nil {
    action := "setting"
    if !hibernate {
      action = "removing"
    }
    return fmt.Errorf("%s hibernation on CNPG cluster %s/%s: %w", action, ns, name, err)
  }

  return nil
}

// DeploymentExists checks whether a deployment exists in the given namespace.
func (k *RealKubeClient) DeploymentExists(ctx context.Context, ns, name string) (bool, error) {
  _, err := k.clientset.AppsV1().Deployments(ns).Get(ctx, name, metav1.GetOptions{})
  if err != nil {
    if apierrors.IsNotFound(err) {
      return false, nil
    }
    return false, fmt.Errorf("checking deployment %s/%s: %w", ns, name, err)
  }
  return true, nil
}

// ExecInDeployment finds the first ready pod for the given deployment and
// executes a command, returning the combined stdout output.
func (k *RealKubeClient) ExecInDeployment(ctx context.Context, ns, deploy string, cmd []string) (string, error) {
  // Get the deployment to find its selector.
  dep, err := k.clientset.AppsV1().Deployments(ns).Get(ctx, deploy, metav1.GetOptions{})
  if err != nil {
    return "", fmt.Errorf("getting deployment %s/%s: %w", ns, deploy, err)
  }

  selector, err := metav1.LabelSelectorAsSelector(dep.Spec.Selector)
  if err != nil {
    return "", fmt.Errorf("parsing label selector for %s/%s: %w", ns, deploy, err)
  }

  pods, err := k.clientset.CoreV1().Pods(ns).List(ctx, metav1.ListOptions{
    LabelSelector: selector.String(),
  })
  if err != nil {
    return "", fmt.Errorf("listing pods for deployment %s/%s: %w", ns, deploy, err)
  }

  // Find the first ready pod.
  var targetPod string
  for _, pod := range pods.Items {
    if isPodReady(&pod) {
      targetPod = pod.Name
      break
    }
  }
  if targetPod == "" {
    return "", fmt.Errorf("no ready pods found for deployment %s/%s", ns, deploy)
  }

  return k.execInPod(ctx, ns, targetPod, cmd)
}

// execInPod executes a command in the first container of a pod and returns stdout.
func (k *RealKubeClient) execInPod(ctx context.Context, ns, pod string, cmd []string) (string, error) {
  req := k.clientset.CoreV1().RESTClient().Post().
    Resource("pods").
    Name(pod).
    Namespace(ns).
    SubResource("exec").
    VersionedParams(&corev1.PodExecOptions{
      Command: cmd,
      Stdout:  true,
      Stderr:  true,
    }, scheme.ParameterCodec)

  exec, err := remotecommand.NewSPDYExecutor(k.restConfig, "POST", req.URL())
  if err != nil {
    return "", fmt.Errorf("creating SPDY executor for pod %s/%s: %w", ns, pod, err)
  }

  var stdout, stderr bytes.Buffer
  if err := exec.StreamWithContext(ctx, remotecommand.StreamOptions{
    Stdout: &stdout,
    Stderr: &stderr,
  }); err != nil {
    return "", fmt.Errorf("exec in pod %s/%s (stderr: %s): %w", ns, pod, stderr.String(), err)
  }

  return stdout.String(), nil
}

// ScaleDeployment sets the replica count for a deployment.
func (k *RealKubeClient) ScaleDeployment(ctx context.Context, ns, name string, replicas int32) error {
  scale, err := k.clientset.AppsV1().Deployments(ns).GetScale(ctx, name, metav1.GetOptions{})
  if err != nil {
    return fmt.Errorf("getting scale for deployment %s/%s: %w", ns, name, err)
  }

  scale.Spec.Replicas = replicas
  _, err = k.clientset.AppsV1().Deployments(ns).UpdateScale(ctx, name, scale, metav1.UpdateOptions{})
  if err != nil {
    return fmt.Errorf("scaling deployment %s/%s to %d: %w", ns, name, replicas, err)
  }

  return nil
}

// ListDeploymentNames returns deployment names in a namespace matching a label selector.
func (k *RealKubeClient) ListDeploymentNames(ctx context.Context, ns, labelSelector string) ([]string, error) {
  deployments, err := k.clientset.AppsV1().Deployments(ns).List(ctx, metav1.ListOptions{
    LabelSelector: labelSelector,
  })
  if err != nil {
    return nil, fmt.Errorf("listing deployments in %s with selector %q: %w", ns, labelSelector, err)
  }

  names := make([]string, 0, len(deployments.Items))
  for _, d := range deployments.Items {
    names = append(names, d.Name)
  }

  return names, nil
}

// GetNodes returns all cluster nodes with their ready status.
func (k *RealKubeClient) GetNodes(ctx context.Context) ([]Node, error) {
  nodeList, err := k.clientset.CoreV1().Nodes().List(ctx, metav1.ListOptions{})
  if err != nil {
    return nil, fmt.Errorf("listing nodes: %w", err)
  }

  nodes := make([]Node, 0, len(nodeList.Items))
  for _, n := range nodeList.Items {
    ready := false
    for _, cond := range n.Status.Conditions {
      if cond.Type == corev1.NodeReady {
        ready = cond.Status == corev1.ConditionTrue
        break
      }
    }
    // Extract the InternalIP address from node status.
    var ip string
    for _, addr := range n.Status.Addresses {
      if addr.Type == corev1.NodeInternalIP {
        ip = addr.Address
        break
      }
    }

    nodes = append(nodes, Node{
      Name:  n.Name,
      IP:    ip,
      Ready: ready,
    })
  }

  return nodes, nil
}

// IsCephNooutSet runs "ceph osd dump" in the rook-ceph-tools deployment and
// checks whether the noout flag is set.
func (k *RealKubeClient) IsCephNooutSet(ctx context.Context) (bool, error) {
  output, err := k.ExecInDeployment(ctx, "rook-ceph", "rook-ceph-tools", []string{"ceph", "osd", "dump"})
  if err != nil {
    return false, fmt.Errorf("checking Ceph noout flag: %w", err)
  }

  return strings.Contains(output, "noout"), nil
}

// isPodReady returns true if the pod is running and its Ready condition is true.
func isPodReady(pod *corev1.Pod) bool {
  if pod.Status.Phase != corev1.PodRunning {
    return false
  }
  for _, cond := range pod.Status.Conditions {
    if cond.Type == corev1.PodReady {
      return cond.Status == corev1.ConditionTrue
    }
  }
  return false
}

// Compile-time interface conformance check.
var _ KubeClient = (*RealKubeClient)(nil)
