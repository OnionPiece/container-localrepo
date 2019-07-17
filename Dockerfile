FROM centos

RUN yum install -y httpd createrepo openssl haproxy git

RUN curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py

RUN python get-pip.py

RUN pip install pypiserver gunicorn

COPY . ./

CMD ["bash", "start.sh"]
