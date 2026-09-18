FROM httpd:2.4-alpine
ARG BACKEND_HOST
COPY index.html /usr/local/apache2/htdocs/
COPY httpd.conf /usr/local/apache2/conf/httpd.conf
RUN sed -i "s/\${BACKEND_HOST}/${BACKEND_HOST}/g" /usr/local/apache2/conf/httpd.conf
