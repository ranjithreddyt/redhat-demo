FROM registry.access.redhat.com/ubi9/nginx-124:latest

COPY src/ /opt/app-root/src/

USER 1001

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]
