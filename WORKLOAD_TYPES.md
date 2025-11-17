# Workload Types Guide

The platform library chart supports multiple Kubernetes workload types. Developers can specify which type to use in their `configuration.yml` file.

## Supported Workload Types

### Deployment (Default)

**Use for:** Stateless applications that can scale horizontally

**Features:**
- Horizontal scaling
- Rolling updates
- Supports HorizontalPodAutoscaler
- No persistent storage per pod

**Example:**
```yaml
workload:
  type: Deployment

deployment:
  replicas: 3
  image:
    repository: myregistry/my-app
    tag: "v1.0.0"
```

**When to use:**
- Web applications
- APIs
- Stateless microservices
- Any service that doesn't need persistent storage per pod

### StatefulSet

**Use for:** Stateful applications that need:
- Stable network identities (hostname)
- Ordered deployment and scaling
- Persistent storage per pod
- Stable storage even when pods are rescheduled

**Features:**
- Stable pod identity (pod-0, pod-1, etc.)
- Ordered creation/deletion
- Persistent volume claims per pod
- Supports HorizontalPodAutoscaler
- Headless service required

**Example:**
```yaml
workload:
  type: StatefulSet

deployment:
  replicas: 3
  image:
    repository: myregistry/database
    tag: "v1.0.0"

statefulset:
  volumeClaimTemplates:
    - name: data
      storageClassName: fast-ssd
      accessModes:
        - ReadWriteOnce
      storage: 10Gi
```

**When to use:**
- Databases (PostgreSQL, MySQL, MongoDB)
- Message queues (RabbitMQ, Kafka)
- Distributed systems requiring stable identities
- Applications needing persistent storage per pod

**Important Notes:**
- StatefulSets require a headless service (service.type: ClusterIP with clusterIP: None)
- Pods are created/deleted in order
- Each pod gets a unique identity (pod-0, pod-1, etc.)
- Volume claims are created automatically per pod

### DaemonSet

**Use for:** Node-level agents that should run on every node

**Features:**
- One pod per node
- Automatic scheduling on new nodes
- Node selector support
- Tolerations support
- Does NOT support HorizontalPodAutoscaler
- Ignores replicas setting

**Example:**
```yaml
workload:
  type: DaemonSet

deployment:
  image:
    repository: myregistry/node-agent
    tag: "v1.0.0"
  # replicas is ignored for DaemonSet

daemonset:
  nodeSelector:
    kubernetes.io/os: linux
  tolerations:
    - key: node-role.kubernetes.io/master
      operator: Exists
      effect: NoSchedule
```

**When to use:**
- Log collectors (Fluentd, Logstash)
- Monitoring agents (Prometheus node exporter)
- Network plugins
- Storage daemons
- Security agents

**Important Notes:**
- `replicas` setting is ignored
- Pods are automatically created on new nodes
- Use nodeSelector to limit which nodes run the pod
- Use tolerations to run on master/control plane nodes

## Configuration Examples

### Deployment Example

```yaml
service:
  name: frontend
  type: ClusterIP
  port: 80
  targetPort: 8080

workload:
  type: Deployment

deployment:
  replicas: 3
  image:
    repository: myregistry/frontend
    tag: "v1.0.0"
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
```

### StatefulSet Example

```yaml
service:
  name: database
  type: ClusterIP
  port: 5432
  targetPort: 5432

workload:
  type: StatefulSet

deployment:
  replicas: 3
  image:
    repository: myregistry/postgres
    tag: "15-alpine"
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 2000m
      memory: 4Gi

statefulset:
  volumeClaimTemplates:
    - name: data
      storageClassName: fast-ssd
      accessModes:
        - ReadWriteOnce
      storage: 20Gi
    - name: logs
      storageClassName: fast-ssd
      accessModes:
        - ReadWriteOnce
      storage: 5Gi

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
  targetCPUUtilizationPercentage: 80
```

### DaemonSet Example

```yaml
service:
  name: node-exporter
  type: ClusterIP
  port: 9100
  targetPort: 9100

workload:
  type: DaemonSet

deployment:
  # replicas is ignored for DaemonSet
  image:
    repository: prom/node-exporter
    tag: "v1.6.0"
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 200m
      memory: 256Mi

daemonset:
  nodeSelector:
    kubernetes.io/os: linux
  tolerations:
    - key: node-role.kubernetes.io/master
      operator: Exists
      effect: NoSchedule
    - key: node-role.kubernetes.io/control-plane
      operator: Exists
      effect: NoSchedule
```

## Feature Comparison

| Feature | Deployment | StatefulSet | DaemonSet |
|---------|-----------|-------------|-----------|
| Replicas | ✅ Configurable | ✅ Configurable | ❌ One per node |
| Scaling | ✅ Horizontal | ✅ Ordered | ❌ Automatic |
| HPA Support | ✅ Yes | ✅ Yes | ❌ No |
| Persistent Storage | ❌ No | ✅ Yes (per pod) | ❌ No |
| Stable Identity | ❌ No | ✅ Yes | ❌ No |
| Ordered Updates | ❌ No | ✅ Yes | ❌ No |
| Node Affinity | ✅ Yes | ✅ Yes | ✅ Yes |
| Tolerations | ✅ Yes | ✅ Yes | ✅ Yes |

## Migration Guide

### From Deployment to StatefulSet

If you need to migrate a Deployment to StatefulSet:

1. **Add workload type:**
```yaml
workload:
  type: StatefulSet
```

2. **Add volume claim templates:**
```yaml
statefulset:
  volumeClaimTemplates:
    - name: data
      storageClassName: fast-ssd
      accessModes:
        - ReadWriteOnce
      storage: 10Gi
```

3. **Update service to headless (if needed):**
```yaml
service:
  type: ClusterIP
  clusterIP: None  # For StatefulSet
```

4. **Regenerate chart and redeploy**

### From Deployment to DaemonSet

1. **Add workload type:**
```yaml
workload:
  type: DaemonSet
```

2. **Remove replicas** (will be ignored)

3. **Add node selector/tolerations:**
```yaml
daemonset:
  nodeSelector:
    kubernetes.io/os: linux
```

4. **Remove autoscaling** (not supported)

5. **Regenerate chart and redeploy**

## Best Practices

1. **Use Deployment by default** - Most applications don't need StatefulSet or DaemonSet features

2. **StatefulSet for databases** - Any application requiring persistent storage per pod

3. **DaemonSet for node agents** - Logging, monitoring, networking agents

4. **Test workload type changes** - Changing workload types requires careful migration

5. **Consider storage** - StatefulSets require storage classes and volume claim templates

6. **HPA limitations** - Only Deployment and StatefulSet support HPA

7. **Service configuration** - StatefulSets often need headless services for stable DNS

## Troubleshooting

### StatefulSet pods not starting

- Check volume claim templates are configured
- Verify storage class exists
- Check pod security contexts
- Review persistent volume claims: `kubectl get pvc`

### DaemonSet not scheduling on all nodes

- Check node selector matches node labels
- Verify tolerations are correct
- Review pod events: `kubectl describe pod <pod-name>`

### HPA not working

- Verify workload type is Deployment or StatefulSet
- Check metrics server is installed
- Review HPA status: `kubectl describe hpa <name>`

