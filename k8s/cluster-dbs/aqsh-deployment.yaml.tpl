apiVersion: apps/v1
kind: Deployment
metadata:
  name: aqsh
  namespace: db-ops
spec:
  replicas: 1
  selector:
    matchLabels:
      app: aqsh
  template:
    metadata:
      labels:
        app: aqsh
    spec:
      serviceAccountName: kube-auth-proxy
      containers:
        - name: aqsh
          image: ghcr.io/null-ptr-exception/aqsh:0.4.0
          env:
            - name: AQSH_MODE
              value: both
            - name: AQSH_BIND
              value: "0.0.0.0:8080"
            - name: AQSH_REDIS_ADDR
              value: "redis:6379"
            - name: AQSH_TASKS_CONFIG
              value: /etc/aqsh/tasks.yaml
            - name: AQSH_TASKS_DIR
              value: /tasks
            - name: AQSH_REQUIRE_IDENTITY
              value: "true"
          ports:
            - containerPort: 8080
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 10
          volumeMounts:
            - name: config
              mountPath: /etc/aqsh
              readOnly: true
            - name: tasks
              mountPath: /tasks
              readOnly: true
        - name: kube-auth-proxy
          image: ghcr.io/rophy/kube-auth-proxy:0.4.1
          env:
            - name: UPSTREAM
              value: "http://localhost:8080"
            - name: TOKEN_REVIEW_URL
              value: "http://${CLUSTER_AUTH_IP}:30080"
            - name: PORT
              value: "4180"
          ports:
            - containerPort: 4180
          livenessProbe:
            httpGet:
              path: /healthz
              port: 4180
            initialDelaySeconds: 5
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /healthz
              port: 4180
            initialDelaySeconds: 5
            periodSeconds: 10
      volumes:
        - name: config
          configMap:
            name: aqsh-config
            items:
              - key: tasks.yaml
                path: tasks.yaml
        - name: tasks
          configMap:
            name: aqsh-config
            items:
              - key: hello.sh
                path: hello.sh
            defaultMode: 0755
