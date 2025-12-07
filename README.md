## Tractus‑X Umbrella
### Deployment Guide

This document summarizes the deployment and build steps used while working on the Tractus‑X umbrella project, the standalone EDC connector, the problems encountered and the fixes applied. It is intended to be a concise, practical guide for developers and operators deploying the project locally (Minikube) or in test clusters.

**Prerequisites**

**1. Deploy the Tractus‑X Umbrella Project**

Manual Deploy
If you already have a working Kubernetes cluster (Minikube, Docker Desktop, or a managed cluster):

```bash
git clone https://github.com/arindamgb-devops/tractus-x-umbrella.git
cd tractus-x-umbrella/charts/umbrella
helm upgrade --install umbrella . -f development-values.yaml \
  -n tractus-x --create-namespace --dependency-update --timeout 15m
```

Automatic Deploy with Terraform + ArgoCD
The repo contains Terraform and GitOps manifests to bootstrap a Minikube environment and ArgoCD application:

```bash
cd /home/arindam/tractus-x-umbrella/terraform
terraform init
terraform apply

# Add host DNS entry for Minikube IP (example helper)
MINIKUBE_IP="$(minikube ip -p tractus)" && sudo ./update-hosts.sh "$MINIKUBE_IP"

# Apply GitOps (ArgoCD manifest)
kubectl apply -f tx-gitops.yaml
```

Notes:

**2. Deploy Standalone Eclipse Dataspace Connector (EDC Connector)**

Build from source and produce container images for the EDC Control Plane and Data Plane.

Build steps (example):

```bash
# Clone the custom EDC connector repo
git clone https://github.com/arindamgb-devops/edc-connector.git

# Use a Gradle container to build reproducibly
docker run -it --rm --name java17-gradle -v ./edc-connector:/edc-connector gradle:8.5-jdk17-jammy bash
cd /edc-connector
./gradlew clean :launchers:edc-connector-custom:buildAll
ls -la launchers/edc-connector-custom/build/libs/
exit

# Build controlplane image
cd edc-connector/launchers/edc-connector-custom
docker build -f Dockerfile.controlplane -t arindamgb/edc-controlplane:0.15.0 .

# Build dataplane image
docker build -f Dockerfile.dataplane -t arindamgb/edc-dataplane:0.15.0 .

docker push arindamgb/edc-controlplane:0.15.0
docker push arindamgb/edc-dataplane:0.15.0
```

Deploy the standalone Helm chart:

```bash
git clone https://github.com/arindamgb-devops/tractus-x-umbrella.git
cd tractus-x-umbrella/charts/standalone-edc
helm upgrade --install standalone-edc . -f values.yaml -n edc-standalone-ns --create-namespace --dependency-update
```

Important: at the time of authoring the standalone deployment, the runtime fails with a missing `Clock` dependency during dependency injection (DI). This indicates that one or more modules that provide core runtime services were not included in the packaged launcher JARs. Thus the Deployment did not run as intended.

**Issues Faced (summary) and Resolutions**

1. **OOMKilled / Memory Pressure**: some jobs and pods were OOMKilled. Solution: Increase memory requests/limits for the affected jobs/pods in the values file.

2. **Ingress pathType validation**: nginx ingress rejects `Prefix` with regex paths. Solution: Use `pathType: ImplementationSpecific` and patch the digital‑twin bundle templates (or set `urlPrefix: \"\"` to avoid the `Prefix` branch). Local patched chart is used for `digital‑twin‑registry`.

3. **Bitnami image deprecation/outdated tags**: some subcharts referenced Bitnami images that were moved/changed. Solution: Override the image repository/tag in `values.yaml` to `bitnamilegacy/*` for affected Postgres charts (e.g., `bpndiscovery-postgresql`, `discoveryfinder-postgresql`).

4. **No pods after install (transitive dependency issue)**: `tx-data-provider` had no pods until dependencies were updated. Solution: Use `--dependency-update` with `helm install/upgrade` so transitive charts are unpacked and installed.

5. **fsnotify "too many open files"**: services such as `smtp4dev`, `bpndiscovery` and `bpdm-pool` hit inotify/file descriptor limits. Solution: Add sysctls (via init container or pod securityContext) to increase `fs.inotify.max_user_instances` and `fs.file-max` (e.g., 8192, 2097152) and/or add capability `SYS_RESOURCE`.

6. **Nested Vault webhook conflicts**: multiple nested Vault instances attempted to create MutatingWebhookConfiguration resources, conflicting with existing `vault-k8s`. Solution: Disable the injector subchart for nested Vault instances in `development-values.yaml` (e.g., set `injector.enabled: false` and `agentInjector.enabled: false`) or run a single top-level Vault.

7. **Post-install testdata job failure (seedTestdata)**: `seedTestdata: true` job failed because an SSI DIM wallet stub endpoint returned a 404/502 during startup. Solution: Set `seedTestdata: false` in `development-values.yaml` while dependent services (wallet stub, dtr) are not yet ready. Re-enable once dependencies are healthy.

8. **Service/Template nil-pointer errors (Vault SecretStore)**: some templates expected nested `vault` keys. Solution: Provide a complete top-level `vault` block with `auth.tokenSecret` and `secretStore.annotations` or explicitly disable top-level vault templating.

9. **Helper template stray characters**: Packaged chart template contained stray `[]` comment that rendered into YAML and corrupted `ingressClassName`. Solution: Fix the template in the packaged chart (move the `[]` comment onto its own line so it doesn't render into a config value).

10. **EDC runtime DI failures (missing core services)**: during local image testing the runtime crashed with DI errors such as missing `Clock`, `HealthCheckService`, `CriterionOperatorRegistry` and `ParticipantContextConfig`. Cause: the launcher JAR did not include modules that provide these services or service provider files were not merged. Solution: include the appropriate modules in the launcher (e.g., `core:common:lib:boot-lib`, `core:common:participant-context-config-core`, `core:common:lib:query-lib`) and `mergeServiceFiles()` in ShadowJar, rebuild the JAR and repackage the images. Also validate `META-INF/services/*` in the produced JAR.

**Troubleshooting & Diagnostics**


```bash
kubectl get pods -n tractus-x -o wide
kubectl describe pod <pod> -n tractus-x
kubectl logs <pod> -n tractus-x
```

If you encounter Helm/Chart errors during umbrella or subchart deployment, run `helm dependency update` for each subchart before installing or upgrading the umbrella chart. Example commands:

```bash
helm dependency update tractus-x-umbrella/charts/bpndiscovery
helm dependency update tractus-x-umbrella/charts/data-persistence-layer-bundle
helm dependency update tractus-x-umbrella/charts/dataspace-connector-bundle
helm dependency update tractus-x-umbrella/charts/digital-twin-bundle
helm dependency update tractus-x-umbrella/charts/digital-twin-registry
helm dependency update tractus-x-umbrella/charts/discoveryfinder
helm dependency update tractus-x-umbrella/charts/identity-and-trust-bundle
helm dependency update tractus-x-umbrella/charts/semantic-hub
helm dependency update tractus-x-umbrella/charts/simple-data-backend
helm dependency update tractus-x-umbrella/charts/tx-data-provider
helm dependency update tractus-x-umbrella/charts/umbrella
```

To access from a remote machine, use the included port-forward helper script. From the repository root run:

```bash
./minikube-helper/port-forward-from-server-to-minikube.sh
```
