# core

![Version: 0.2.0](https://img.shields.io/badge/Version-0.2.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 35.0.5](https://img.shields.io/badge/AppVersion-35.0.5-informational?style=flat-square)

A Helm chart for Kubernetes

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| indigo423 | <ronny@no42.org> | <https://github.com/indigo423> |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` |  |
| autoscaling.enabled | bool | `false` |  |
| autoscaling.maxReplicas | int | `1` |  |
| autoscaling.minReplicas | int | `1` |  |
| configRenderer.image.pullPolicy | string | `"IfNotPresent"` |  |
| configRenderer.image.repository | string | `"docker.io/alpine"` |  |
| configRenderer.image.tag | string | `"3.19"` |  |
| elasticsearch.auth.existingSecret | string | `""` |  |
| elasticsearch.enabled | bool | `false` |  |
| elasticsearch.indexStrategy | string | `"monthly"` |  |
| elasticsearch.url | string | `""` |  |
| extraConfigFiles | object | `{}` |  |
| fullnameOverride | string | `""` |  |
| httpRoute.annotations | object | `{}` |  |
| httpRoute.enabled | bool | `false` |  |
| httpRoute.hostnames[0] | string | `"chart-example.local"` |  |
| httpRoute.parentRefs[0].name | string | `"gateway"` |  |
| httpRoute.parentRefs[0].sectionName | string | `"http"` |  |
| httpRoute.rules[0].matches[0].path.type | string | `"PathPrefix"` |  |
| httpRoute.rules[0].matches[0].path.value | string | `"/"` |  |
| image.pullPolicy | string | `"IfNotPresent"` |  |
| image.repository | string | `"docker.io/opennms/horizon"` |  |
| image.tag | string | `""` |  |
| imagePullSecrets | list | `[]` |  |
| ingress.annotations | object | `{}` |  |
| ingress.className | string | `""` |  |
| ingress.enabled | bool | `false` |  |
| ingress.hosts[0].host | string | `"chart-example.local"` |  |
| ingress.hosts[0].paths[0].path | string | `"/"` |  |
| ingress.hosts[0].paths[0].pathType | string | `"ImplementationSpecific"` |  |
| ingress.tls | list | `[]` |  |
| instanceId | string | `"OpenNMS"` |  |
| javaOpts | string | `""` |  |
| kafka.auth.enabled | bool | `false` |  |
| kafka.auth.existingSecret | string | `""` |  |
| kafka.auth.mechanism | string | `"SCRAM-SHA-512"` |  |
| kafka.bootstrapServers | string | `""` |  |
| kafka.extraProperties | object | `{}` |  |
| kafka.tls.enabled | bool | `false` |  |
| kafka.tls.existingSecret | string | `""` |  |
| livenessProbe.failureThreshold | int | `6` |  |
| livenessProbe.initialDelaySeconds | int | `90` |  |
| livenessProbe.periodSeconds | int | `30` |  |
| livenessProbe.tcpSocket.port | string | `"webui"` |  |
| livenessProbe.timeoutSeconds | int | `5` |  |
| nameOverride | string | `""` |  |
| nodeSelector | object | `{}` |  |
| persistence.accessMode | string | `"ReadWriteOnce"` |  |
| persistence.annotations | object | `{}` |  |
| persistence.enabled | bool | `true` |  |
| persistence.size | string | `"50Gi"` |  |
| persistence.storageClassName | string | `""` |  |
| podAnnotations | object | `{}` |  |
| podLabels | object | `{}` |  |
| podSecurityContext | object | `{}` |  |
| postgresql.auth.existingSecret | string | `""` |  |
| postgresql.auth.password | string | `"Change_Me_OpenNMS_DBA"` |  |
| postgresql.auth.superuserName | string | `"postgres"` |  |
| postgresql.auth.superuserPassword | string | `"Change_Me_Postgres"` |  |
| postgresql.auth.username | string | `"opennms_dba"` |  |
| postgresql.database | string | `"opennms"` |  |
| postgresql.host | string | `"cluster-helm-lint-rw.default.svc.cluster.local"` |  |
| postgresql.port | int | `5432` |  |
| prometheus.jmxExporter.enabled | bool | `false` |  |
| prometheus.jmxExporter.port | int | `9299` |  |
| prometheusRemoteWriter.auth.existingSecret | string | `""` |  |
| prometheusRemoteWriter.enabled | bool | `false` |  |
| prometheusRemoteWriter.kar.url | string | `""` |  |
| prometheusRemoteWriter.readUrl | string | `""` |  |
| prometheusRemoteWriter.version | string | `"0.3.2"` |  |
| prometheusRemoteWriter.writeUrl | string | `""` |  |
| readinessProbe.failureThreshold | int | `20` |  |
| readinessProbe.httpGet.path | string | `"/opennms/login.jsp"` |  |
| readinessProbe.httpGet.port | string | `"webui"` |  |
| readinessProbe.initialDelaySeconds | int | `90` |  |
| readinessProbe.periodSeconds | int | `5` |  |
| readinessProbe.timeoutSeconds | int | `3` |  |
| resources | object | `{}` |  |
| securityContext | object | `{}` |  |
| selectorLabels."app.opennms.org/component" | string | `"core"` |  |
| service.karaf.port | int | `8101` |  |
| service.port | int | `8980` |  |
| service.type | string | `"ClusterIP"` |  |
| service.webui.port | int | `8980` |  |
| serviceAccount.annotations | object | `{}` |  |
| serviceAccount.automount | bool | `true` |  |
| serviceAccount.create | bool | `true` |  |
| serviceAccount.name | string | `""` |  |
| timeseriesStrategy | string | `"rrd"` |  |
| timezone | string | `"UTC"` |  |
| tolerations | list | `[]` |  |
| volumeMounts | list | `[]` |  |
| volumes | list | `[]` |  |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
