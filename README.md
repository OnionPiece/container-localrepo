To run, e.g. :

    # suppose image built with name yumrepo
    docker run -d --name private-yumrepo \
        -e GITLAB_IP=<YOUR_GITLAB_IP> \
        -e PRIVATE_TOKEN=d6T5bNvoPU_6WfdodCLr \
        -e GIT_USER=root -e GIT_PASS=Password \
        -e POP_PROJECTS="true" \
        -v /path/to/rpms/and/download/files:/var/www/html \
        -v /path/to/projects/to/pop:/gitlab_projects
        yumrepo

where:

  - path inside container, /var/www/html and /gitlab_projects are hard coded.
  - /path/to/rpms/and/download/files, looks like:

        the-path/
           gcc-4.8.5-36.el7.x86_64.rpm
           glibc-2.17-260.el7_6.3.x86_64.rpm
           ...
           go/
              go1.10.8.linux-amd64.tar.gz
           acassen/
              keepalived/
                 tar.gz/
                    v2.0.10
           ...

    rpms and files for downloading can put there. And for files to be downloaded, you should manually create directory tree for url path, like https://codeload.github.com/acassen/keepalived/tar.gz/v2.0.10.

    If you want use link instead of directly copy things to the path, try to create hard links for files in mount path.

  - environment variable GITLAB_IP is optional.

    For case, a Dockerfile contains `curl` and `git clone` , they both try to access github.com, and resources they want are supplied by two local cache containers, like gitlab and yumrepo.

    To work with this, your gitlab container should start with, e.g. :

        --env GITLAB_OMNIBUS_CONFIG="external_url 'https://<HOSTNAME_YOU_PREFER>'; nginx['listen_https'] = false; nginx['listen_port'] = 80" \

  - environment variable POP_PROJECTS is optional.

    For case where you can clone projects from github to local, populate to gitlab, and speed up `git clone` in docker image building.
    To make projects population work:

    - GITLAB_IP, PRIVATE_TOKEN, GIT_USER, GIT_PASS are needed. You can create and get PRIVATE_TOKEN in gitlab  > User Settings > Access Tokens.
    - POP_PROJECTS needs be "true".
    - You need mount path which contains projects to be populated to container path /gitlab_projects

    The projects directory can contain multiple projects, like:

        the-path/
            Manifests
            etcd
            moby
            etcd-io

    And Manifests file is needed, which format looks like:

        # go get github.com/docker/docker
        moby docker/docker https://github.com/moby/moby.git

        # go get github.com/etcd-io/etcd
        etcd-io - https://github.com/etcd-io/etcd

        # go get github.com/coreos/etcd
        etcd - https://github.com/coreos/etcd

    where:

      -  '#' starts a annotation line
      - moby, etcd-io, etcd are folder names in the path
      - docker/docker are group/project names which will be used to create in gitlab.
      - '-' means get group/project name from the follow url, like etcd-io is group and etcd is project for folder etcd-io.

To use as yum repo(in other client containers):

    cd /etc/yum.repos.d/
    # disable or remove all other repos
    curl -o private.repo http://YUMREPO_HOSTNAME/private.repo
    yum install whatever-in-private-repo

To use as file download server, e.g.:

    # in other client containers:
    curl -k -o go.tar.gz https://SERVER_IP/go/go1.10.8.linux-amd64.tar.gz