# external-dns-technitium - DNS Management

## Overview

ExternalDNS is a Kubernetes controller that automatically manages DNS records based on Kubernetes resources. The technitium variant integrates with Technitium DNS server to provide dynamic DNS management, ensuring that DNS records are automatically created, updated, and deleted as services are deployed or removed.

## Prerequisites

- Technitium DNS server deployed and operational (dependsOn: technitium)
- API credentials for Technitium DNS server

## Troubleshooting

1. **DNS records not being created**

   - **Symptom**: Services deployed but no DNS records appear
   - **Resolution**: Check Technitium DNS server connectivity and API credentials

1. **API authentication errors**

   - **Symptom**: Authentication failures in logs
   - **Resolution**: Verify API credentials in the Technitium DNS server configuration

## References

- [ExternalDNS Documentation](https://github.com/kubernetes-sigs/external-dns)
- [Technitium DNS Documentation](https://technitium.com/dns/)
