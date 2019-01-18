# Traefik ingress controller for Kubernetes

- [Traefik ingress controller for Kubernetes](#traefik-ingress-controller-for-kubernetes)
  - [Terraform initialization](#terraform-initialization)
  - [Apply Terraform plan](#apply-terraform-plan)
  - [Managing persistent volumes](#managing-persistent-volumes)
    - [Change reclaim policy for application volumes](#change-reclaim-policy-for-application-volumes)
    - [Delete persistent volumes](#delete-persistent-volumes)

Terraform configuration for deploying Traefik ingress controller in a Kubernetes cluster

## Terraform initialization

Copy [terraform.tfvars.example](terraform.tfvars.example) file to `terraform.tfvars` and set input variables values as per your needs. Then initialize Terraform with `init` command:

```shell
terraform init -backend-config "bucket=$BUCKET_NAME" -backend-config "prefix=apps/traefik" -backend-config "region=$REGION"
```

- `$REGION` should be replaced with a region name.
- `$BUCKET_NAME` should be replaced with a GCS Terraform state storage bucket name.

## Apply Terraform plan

To apply Terraform plan, run:

```shell
terraform apply
```

## Managing persistent volumes

Some of the included services require persistent storage, configured through Persistent Volumes that specify which disks your cluster has access to.

Storage changes after installation need to be manually handled by your cluster administrators. Automated management of these volumes after installation is not handled by the deployment scripts.

> **IMPORTANT**: you may experience a total data loss if these changes are not applied properly. Specifically, if you don't change the default `Delete` [reclaimPolicy](https://kubernetes.io/docs/concepts/storage/storage-classes/#reclaim-policy) for [PersistentVolumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#persistent-volumes) to `Retain`, the inderlying [Google Persistent Disk](https://cloud.google.com/compute/docs/disks/) will be completely destroyed by GCE upon destruction of a Kubernetes application stack.

### Change reclaim policy for application volumes

Find the volumes/claims that are being used, and change the `reclaimPolicy` for each from `Delete` to `Retain`:

```shell
$ kubectl get pv | grep datadir-consul
pvc-d4184653-179a-11e9-ad5f-42010a80029a   1Gi        RWO            Delete           Bound     kube-system/datadir-consul-0   standard                 9h

$ kubectl patch pv pvc-d4184653-179a-11e9-ad5f-42010a80029a -p "{\"spec\":{\"persistentVolumeReclaimPolicy\":\"Retain\"}}"
persistentvolume "pvc-d4184653-179a-11e9-ad5f-42010a80029a" patched

$ kubectl get pv -n kube-system | grep datadir-consul
pvc-d4184653-179a-11e9-ad5f-42010a80029a   1Gi        RWO            Retain           Bound     kube-system/datadir-consul-0   standard                 9h
```

### Delete persistent volumes

After you uninstall this plan from the cluster, and **you are completely sure** you don't need its persisten volumes anymore, you can delete them using following commands:

```shell
$ kubectl get pvc | grep datadir-consul
datadir-consul-0   Bound     pvc-d4184653-179a-11e9-ad5f-42010a80029a   1Gi        RWO            standard       15h

$ kubectl delete pvc datadir-consul-0 -n kube-system
persistentvolumeclaim "datadir-consul-0" deleted

$ gcloud compute disks list --filter="-users:*"
NAME                                                             ZONE           SIZE_GB  TYPE         STATUS
gke-dev-a3f54e52-dynam-pvc-e41dcd6c-179a-11e9-ad5f-42010a80029a  us-central1-a  1        pd-standard  READY

$ gcloud compute disks delete gke-dev-a3f54e52-dynam-pvc-e41dcd6c-179a-11e9-ad5f-42010a80029a --zone=us-central1-a
The following disks will be deleted:
 - [gke-dev-a3f54e52-dynam-pvc-e41dcd6c-179a-11e9-ad5f-42010a80029a]
in [us-central1-a]

Do you want to continue (Y/n)?  y

Deleted [https://www.googleapis.com/compute/v1/projects/mtm-default-1/zones/us-central1-a/disks/gke-dev-a3f54e52-dynam-pvc-e41dcd6c-179a-11e9-ad5f-42010a80029a].
```
