# RedisInsight - Visualization Tool

## Overview

RedisInsight is a powerful visualization and management tool for Redis databases. In the spruyt-labs homelab infrastructure, RedisInsight provides comprehensive monitoring, analysis, and administration capabilities for all Redis-compatible data stores.

## Prerequisites

- Kubernetes cluster with Flux CD installed
- Redis or Valky instances available
- Network connectivity between RedisInsight and data stores
- Proper RBAC permissions for monitoring
- Browser access for web interface

## Operation

### Procedures

1. **Database connection management**:

   ```bash
   # Check connected databases
   kubectl logs -n redisinsight <redisinsight-pod> | grep "connected"

   # Monitor query performance
   kubectl logs -n redisinsight <redisinsight-pod> | grep "performance"
   ```

2. **User access management**:

   ```bash
   # Check authentication logs
   kubectl logs -n redisinsight <redisinsight-pod> | grep "authentication"

   # Monitor active sessions
   kubectl logs -n redisinsight <redisinsight-pod> | grep "session"
   ```

3. **Configuration updates**:

   ```bash
   # Update RedisInsight configuration
   # Edit values.yaml, commit, then: flux reconcile kustomization redisinsight --with-source

   # Restart pods for configuration changes
   kubectl rollout restart deployment redisinsight -n redisinsight
   ```

## Troubleshooting

### Common Issues

1. **Database connection failures**:

   - **Symptom**: Unable to connect to Redis instances
   - **Diagnosis**: Check network connectivity and credentials
   - **Resolution**: Verify Cilium network policies and authentication

2. **Authentication problems**:

   - **Symptom**: Login failures or permission errors
   - **Diagnosis**: Check authentication configuration
   - **Resolution**: Verify user credentials and RBAC policies

3. **Performance bottlenecks**:

   - **Symptom**: Slow query execution or timeouts
   - **Diagnosis**: Monitor resource usage and query patterns
   - **Resolution**: Scale resources or optimize queries

4. **Web interface issues**:

   - **Symptom**: UI not loading or displaying errors
   - **Diagnosis**: Check browser console and service logs
   - **Resolution**: Verify service configuration and browser compatibility

## Maintenance

### Updates

```bash
# Update RedisInsight using Flux
flux reconcile kustomization redisinsight --with-source

# Check update status
kubectl get helmreleases -n redisinsight
```

### Database Management

```bash
# Add new database connection
kubectl apply -f new-database-config.yaml

# Remove database connection
kubectl delete -f old-database-config.yaml
```

## References

- [RedisInsight Documentation](https://redis.io/docs/latest/)
- [RedisInsight GitHub](https://github.com/RedisInsight/RedisInsight)
- [Redis Commands Reference](https://redis.io/commands)
- [Kubernetes Monitoring Guide](https://kubernetes.io/docs/tasks/debug/)
