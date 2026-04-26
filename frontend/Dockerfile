FROM nginxinc/nginx-unprivileged:alpine-slim
RUN rm /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/nginx.conf
COPY index.html favicon.png /usr/share/nginx/html/
EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]