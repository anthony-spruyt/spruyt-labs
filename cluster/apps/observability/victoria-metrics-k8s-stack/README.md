# Handling Orphaned Resources

## Delete Rules

Find the rule

```bash
kubectl get vmrule -n {NAMESPACE}
```

Delete the rules

```bash
kubectl delete vmrule {NAME} -n {NAMESPACE}
```

## Delete Scrape Targets

Find the orphaned resources

```bash
kubectl get vmservicescrapes,vmpodscrapes,vmnodescrapes, \
  vmstaticscrapes,vmscrapeconfigs -A
```

Delete the scrape targets, example type vmpodscrape

```bash
kubectl delete vmpodscrape {NAME} -n {NAMESPACE}
```

## Restart Pods

Restart vmagent and vmalert
