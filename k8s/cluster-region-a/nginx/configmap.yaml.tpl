apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
  namespace: db-ops
data:
  nginx.conf: |
    worker_processes auto;
    error_log /var/log/nginx/error.log warn;
    pid /tmp/nginx.pid;

    events {
      worker_connections 1024;
    }

    # HTTP gateway: routes /mariadb/* and /mongodb/* to respective aqsh services
    http {
      access_log /var/log/nginx/access.log;
      client_body_temp_path /tmp/client_temp;
      proxy_temp_path /tmp/proxy_temp;
      fastcgi_temp_path /tmp/fastcgi_temp;
      uwsgi_temp_path /tmp/uwsgi_temp;
      scgi_temp_path /tmp/scgi_temp;

      # Preserve %2F encoding: use $request_uri (raw) instead of $uri (decoded)
      map $request_uri $mariadb_uri {
        ~^/mariadb(/.*)$  $1;
        default           "";
      }
      map $request_uri $mongodb_uri {
        ~^/mongodb(/.*)$  $1;
        default           "";
      }

      upstream aqsh_mariadb {
        server aqsh-mariadb.db-ops.svc.cluster.local:4180;
      }
      upstream aqsh_mongodb {
        server aqsh-mongodb.db-ops.svc.cluster.local:4180;
      }

      server {
        listen 80;

        location /mariadb/ {
          proxy_pass http://aqsh_mariadb$mariadb_uri;
          proxy_set_header Host $host;
          proxy_set_header Authorization $http_authorization;
          proxy_pass_header Authorization;
        }

        location /mongodb/ {
          proxy_pass http://aqsh_mongodb$mongodb_uri;
          proxy_set_header Host $host;
          proxy_set_header Authorization $http_authorization;
          proxy_pass_header Authorization;
        }

        location /healthz {
          return 200 "ok\n";
          add_header Content-Type text/plain;
        }
      }
    }

    # Stream (TCP) proxy: cross-region DB replication inbound
    # Region-B slaves connect here to reach region-A primaries
    stream {
      server {
        listen 30092;
        proxy_pass mongodb.mongo-1.svc.cluster.local:27017;
      }
      server {
        listen 30094;
        proxy_pass mongodb.mongo-2.svc.cluster.local:27017;
      }
      server {
        listen 30096;
        proxy_pass mongodb.mongo-3.svc.cluster.local:27017;
      }
      server {
        listen 30093;
        proxy_pass mariadb.mariadb-1.svc.cluster.local:3306;
      }
      server {
        listen 30095;
        proxy_pass mariadb.mariadb-2.svc.cluster.local:3306;
      }
      server {
        listen 30097;
        proxy_pass mariadb.mariadb-3.svc.cluster.local:3306;
      }
    }
