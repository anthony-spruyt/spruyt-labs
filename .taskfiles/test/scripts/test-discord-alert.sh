#!/bin/bash
# Test Discord alerting by creating a crashlooping pod
# This triggers KubePodCrashLooping alert which routes to Discord

set -euo pipefail

POD_NAME="alert-test-$(date +%s)"

echo "Creating crashloop test pod: $POD_NAME"
kubectl run "$POD_NAME" -n dev-debug --image=busybox --restart=Always -- /bin/sh -c "exit 1"

echo ""
echo "Pod created. It will crash loop and trigger KubePodCrashLooping alert."
echo "Alert has 'for: 15m' duration, so you'll need to wait ~15 minutes."
echo ""
echo "To monitor alert status:"
echo "  kubectl exec -n observability vmalertmanager-victoria-metrics-k8s-stack-0 -c alertmanager -- \\"
echo "    wget -qO- 'http://localhost:9093/api/v2/alerts' | grep -i crashloop"
echo ""
echo "To clean up:"
echo "  task test:discord-alert-cleanup"
echo "  # or manually: kubectl delete pod $POD_NAME"
echo ""
echo "Pod name for cleanup: $POD_NAME"
