FROM centos

RUN yum install -y httpd createrepo openssl haproxy git

COPY . ./

CMD ["bash", "start.sh"]
