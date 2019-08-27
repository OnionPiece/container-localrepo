FROM centos

RUN yum install -y httpd createrepo openssl haproxy git epel-release && \
    yum install -y python-pip && \
    pip install -i https://pypi.tuna.tsinghua.edu.cn/simple pypiserver gunicorn && \
    yum clean all

#RUN curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
#
#RUN python get-pip.py
#
#RUN pip install pypiserver gunicorn

COPY Dockerfile popPorjects.sh selfCheck.sh start.sh ./

CMD ["bash", "start.sh"]
