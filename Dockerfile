apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: generate-apply-knative
  namespace: tekton-tasks
spec:
  params:
  - default: ""
    name: APP_NAME
    type: string
  - default: ""
    name: NAMESPACE
    type: string
  - default: ""
    name: APP_IMAGE
    type: string
  results:
    - name: revision
    - name: url


  steps:
  - env:
    - name: HOME
      value: /tekton/home/
    - name: APP_NAME
      value: $(params.APP_NAME)
    - name: APP_IMAGE
      value: $(params.APP_IMAGE)
    image: yqimage
    name: generate-knative
    script: |
      #!/usr/bin/env bash

      folder_name="knative"
      mkdir -p "$folder_name"


      cp /configmap-knative/knative.yaml /$folder_name/$APP_NAME.yaml

      yq eval '.metadata.name = "$(params.APP_NAME)"' -i /$folder_name/$APP_NAME.yaml
      yq eval '.metadata.namespace = "$(params.NAMESPACE)"' -i /$folder_name/$APP_NAME.yaml
      yq eval '.spec.template.spec.containers[0].image = "$(params.APP_IMAGE)"' -i /$folder_name/$APP_NAME.yaml

      cat /$folder_name/$APP_NAME.yaml

    volumeMounts:
      - name: knative-volume
        mountPath: /knative
      - name: configmap-volume
        mountPath: /configmap-knative
    securityContext:
      runAsNonRoot: true
      runAsUser: 65532
      allowPrivilegeEscalation: false
      capabilities:
        drop:
          - "ALL"
      seccompProfile:
        type: "RuntimeDefault"

  - name: kubectl-apply
    image: kubectl-image
    env:
    - name: NAMESPACE
      value: $(params.NAMESPACE)
    - name: APP_NAME
      value: $(params.APP_NAME)

    securityContext:
      runAsNonRoot: true
      runAsUser: 65532
      allowPrivilegeEscalation: false
      capabilities:
        drop:
          - "ALL"
      seccompProfile:
        type: "RuntimeDefault"
    script: |
      #!/usr/bin/env sh
      
      kubectl apply -f /knative/$(params.APP_NAME).yaml

      kubectl wait --for=condition=Ready --timeout=2m ksvc/$(params.APP_NAME) -n $(params.NAMESPACE)
      

    volumeMounts:
      - name: knative-volume
        mountPath: /knative


  volumes:
    - name: knative-volume
      emptyDir: {}
    - name: configmap-volume
      configMap:
        name: knative
