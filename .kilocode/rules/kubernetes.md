# kubernetes.md

kubectl usage rules

## Guidelines

- When working with CRDs, resouces or charts always first confirm the spec's beforehand
- Use CLI commands such as
  - > kubectl api-resources
  - > kubectl get {resource_type} {resource_name} -n {namespace} -o yaml
  - > kubectl explain {spec}
- Use context7 or web search / scrape tools to validate helm chart values and documentation
