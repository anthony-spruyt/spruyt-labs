#!/usr/bin/env bash
set -euo pipefail

echo "Reconciling all Git sources..."
for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
  for source in $(flux get source git --namespace "$ns" | awk 'NR>1 {print $1}'); do
    [ -n "$source" ] && echo "↪️  $ns/$source" && flux reconcile source git "$source" --namespace "$ns" || echo "⚠️  Failed to reconcile $ns/$source"
  done
done

echo ""
echo "Reconciling all Kustomizations..."
for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
  for kustom in $(flux get kustomizations --namespace "$ns" | awk 'NR>1 {print $1}'); do
    [ -n "$kustom" ] && echo "↪️  $ns/$kustom" && flux reconcile kustomization "$kustom" --namespace "$ns" || echo "⚠️  Failed to reconcile $ns/$kustom"
  done
done

echo ""
echo "Reconciling all HelmReleases..."
for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
  for helm in $(flux get helmreleases --namespace "$ns" | awk 'NR>1 {print $1}'); do
    [ -n "$helm" ] && echo "↪️  $ns/$helm" && flux reconcile helmrelease "$helm" --namespace "$ns" || echo "⚠️  Failed to reconcile $ns/$helm"
  done
done

echo ""
echo "✅ Flux reconciliation complete."
