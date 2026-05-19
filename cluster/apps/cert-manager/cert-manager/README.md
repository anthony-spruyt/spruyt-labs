# cert-manager - Certificate Management

## Overview

cert-manager is a native Kubernetes certificate management controller that automates the management and issuance of TLS certificates. It integrates with various issuers including Let's Encrypt, HashiCorp Vault, and private CAs to provide certificates for ingress resources and other services.

## Prerequisites

- DNS records properly configured for domains

## Troubleshooting

1. **Certificate issuance failures**

   - **Symptom**: Certificates stuck in "Pending" state
   - **Resolution**: Check issuer status and challenge resolution; verify DNS records and issuer configuration

2. **DNS challenge timeouts**

   - **Symptom**: Certificate issuance times out
   - **Resolution**: Verify DNS records and challenge solver configuration

3. **Rate limit errors**

   - **Symptom**: Let's Encrypt rate limit errors
   - **Resolution**: Reduce request frequency or use staging environment

## References

- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
