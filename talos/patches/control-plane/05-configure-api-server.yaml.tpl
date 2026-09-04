{{- if semverCompare ">=1.14.0-0" (default .TalosVersion .Node.RuntimeData.TalosVersion) }}
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
# OIDC authentication via Authentik for Headlamp user impersonation. v1.14 rejects the
# oidc-* apiserver flags and takes structured AuthenticationConfiguration instead.
# The empty prefixes reproduce the flag defaults: an email username claim is not
# issuer-prefixed, and oidc-groups-prefix defaulted to empty.
# https://kubernetes.io/docs/reference/access-authn-authz/authentication/#using-authentication-configuration
configuration:
  apiVersion: apiserver.config.k8s.io/v1beta1
  kind: AuthenticationConfiguration
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
{{- else }}
cluster:
  apiServer:
    certSANs:
{{- range .Data.apiServerCertSans }}
      - {{ . }}
{{- end }}
    extraArgs:
      # https://kubernetes.io/docs/tasks/extend-kubernetes/configure-aggregation-layer/
      enable-aggregator-routing: true
      # https://kubernetes.io/docs/reference/command-line-tools-reference/feature-gates/
      feature-gates: "MutatingAdmissionPolicy=true,WatchList=true,WatchListClient=true"
      runtime-config: admissionregistration.k8s.io/v1beta1=true
      # OIDC authentication via Authentik for Headlamp user impersonation
      # https://kubernetes.io/docs/reference/access-authn-authz/authentication/#openid-connect-tokens
      oidc-issuer-url: "https://auth.{{ .Data.externalDomain }}/application/o/headlamp/"
      oidc-client-id: "{{ .Data.headlampOidcClientId }}"
      oidc-username-claim: "email"
      oidc-groups-claim: "groups"
{{- end }}
