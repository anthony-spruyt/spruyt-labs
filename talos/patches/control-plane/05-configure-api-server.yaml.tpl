---
apiVersion: v1alpha1
kind: KubeAPIServerConfig
certExtraSANs:
{{- range .Data.apiServerCertSans }}
  - {{ . }}
{{- end }}
extraArgs:
  # https://kubernetes.io/docs/tasks/extend-kubernetes/configure-aggregation-layer/
  enable-aggregator-routing: true
  # https://kubernetes.io/docs/reference/command-line-tools-reference/feature-gates/
  feature-gates: "MutatingAdmissionPolicy=true,WatchList=true,WatchListClient=true"
  runtime-config: admissionregistration.k8s.io/v1beta1=true
---
apiVersion: v1alpha1
kind: KubeAuthenticationConfig
# OIDC authentication via Authentik for Headlamp user impersonation. The empty prefixes
# are deliberate: an email username claim is not issuer-prefixed, and the groups prefix
# is empty.
# https://kubernetes.io/docs/reference/access-authn-authz/authentication/#using-authentication-configuration
configuration:
  apiVersion: apiserver.config.k8s.io/v1beta1
  kind: AuthenticationConfiguration
  # AuthConfig is merge:"replace", so this block substitutes Talos' generated one rather
  # than merging into it. Anything Talos would have supplied has to be restated here or it
  # is silently dropped. The apiserver's startup, readiness and liveness probes issue
  # unauthenticated GETs and 401 unless anonymous access reaches these three paths.
  # Kubernetes enforces the allowlist at the authentication layer, so nothing outside
  # these paths is anonymously reachable regardless of RBAC.
  anonymous:
    enabled: true
    conditions:
      - path: /livez
      - path: /readyz
      - path: /healthz
  jwt:
    - issuer:
        url: "https://auth.{{ .Data.externalDomain }}/application/o/headlamp/"
        audiences:
          - "{{ .Data.headlampOidcClientId }}"
      claimMappings:
        username:
          claim: "email"
          prefix: ""
        groups:
          claim: "groups"
          prefix: ""
