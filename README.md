## Target
To support cache/private-local-repo for:

  - yum install packages
  - curl/wget to download files
  - git clone projects cloned from github
  - (potential) go get projects cloned from github

which can help speed up docker build for developing, but not for build image to deliver/release, since to make `go get` work, you may need to inject ssh keys into intermedia layers.

## Prepare

### (Optional) Start a gitlab container, e.g. :

    docker run --detach \
	--net <NETWORK_YOU_PREFER> \
	--hostname gitlab.local.io \
	--name gitlab \
        --env GITLAB_OMNIBUS_CONFIG="external_url 'https://gitlab.local.io'; nginx['listen_https'] = false; nginx['listen_port'] = 80" \
	--volume <PATH_YOU_PREFER>/config:/etc/gitlab \
	--volume <PATH_YOU_PREFER>/logs:/var/log/gitlab \
	--volume <PATH_YOU_PREFER>/data:/var/opt/gitlab \
	gitlab/gitlab-ce:latest

### rpm packages and files for downloading

To get .rpm packages, e.g. :

    yum install --downloadonly --downloadonly=. haproxy

or:

    yum reinstall --downloadonly --downloaddir=. haproxy

Put your .rpm packages to a directory which will be mount to oncCache container later.

For your files for downloading, they need be put into the same directory, but maybe with subdirectories to indicate url path for downloading.
So the directory may looks like:

    /path/to/rpms/and/download/files
        gcc-4.8.5-36.el7.x86_64.rpm
        glibc-2.17-260.el7_6.3.x86_64.rpm
        ...
        (for https://dl.google.com/go/go1.10.8.linux-amd64.tar.gz)
        go/
            go1.10.8.linux-amd64.tar.gz
        (for https://codeload.github.com/acassen/keepalived/tar.gz/v2.0.10)
        acassen/
            keepalived/
                tar.gz/
                    v2.0.10


If you want use link instead of directly copy things to the path, try to create hard links for files in mount path, **symbolic link will not work.**

### Projects cloned from github

#### POP_PROJECT, the automatic way

*This part is for loading projects you cloned from github, to gitlab container automatically. If you prefer import manually, check next section.*

Get projects you need into another directory which will be mount to oneCache container later.

You may like to create a subdirectory to manage projects, that's ok. e.g.::

    /path/to/github/projects
        Manifests
        kubernetes/
            go-client
            api
            apimachinery
        coreos/
            etcd
        etcd-io/
            etcd

About Manifests format, check below.

#### Manually import

If you choose to import projects into gitlab manually, you also need a directory contains Manifests to mount to oneCache container.

About Manifests format, check below.

#### Manifests

Manifests format looks like, e.g.:

    # go get github.com/docker/docker
    moby docker/docker https://github.com/moby/moby.git

    # go get github.com/etcd-io/etcd
    etcd-io/etcd - https://github.com/etcd-io/etcd

    # go get github.com/coreos/etcd
    coreos/etcd - https://github.com/coreos/etcd

where:

  - '#' starts a annotation line
  - moby, etcd-io/etcd, coreos/etcd are subdirectory names in the path
  - docker/docker are group/project names which will be used to create in gitlab.
  - '-' means get group/project name from the follow url, like etcd-io is group name and etcd is project name for project in subdirectory etcd-io/etcd.

For automatic way, only projects list in Manifests files will be populated to gitlab.

And for manual way, Manifests records projects which are supplied in gitlab.

When oneCache container starts, it check Manifests, read projects group and project names, to build ACL rules to match request urls. So for git request, if target project is in gitlab, oneCache will route request to gitlab; otherwise, it will route request to github.

Only project master branch and tags will be pushed into gitlab.

## To Run

To run, e.g. :

    # suppose image built with name onecache
    docker run -d --name private-repo \
        -e GITLAB_IP=<YOUR_GITLAB_IP> \
        -e PRIVATE_TOKEN=d6T5bNvoPU_6WfdodCLr \
        -e GIT_USER=root -e GIT_PASS=Password \
        -e POP_PROJECTS="true" \
        -v /path/to/rpms/and/download/files:/var/www/html \
        -v /path/to/projects/to/pop:/gitlab_projects
        onecache

where:

  - path inside container, /var/www/html and /gitlab_projects are hard coded.
  - environment variable POP_PROJECTS is optional, and stands for enable importing projects into gitlab automatically or not.

    To enable , set this to "true", and

      - set GITLAB_IP, PRIVATE_TOKEN, GIT_USER, GIT_PASS. You can create and get PRIVATE_TOKEN in gitlab  > User Settings > Access Tokens.
      - mount path which contains projects to be imported to container path /gitlab_projects

## How to use

After you setup oneCache container, you need assign --network and --add-host options for docker build or run command.

#### yum repo

To use as yum repo(in other client containers):

    cd /etc/yum.repos.d/
    # disable or remove all other repos
    curl -o private.repo http://ONECACHE_CONTAINER_HOSTNAME_OR_IP/private.repo
    yum install whatever-in-private-repo

#### download server

To use as file download server, e.g.:

    # in other client containers:
    curl -k -o go.tar.gz https://SERVER_IP/go/go1.10.8.linux-amd64.tar.gz

#### git repo

To use as git repo:

    git config --global http.sslVerify false
    git clone https://github.com/<PATH/TO/PROJECTS/YOU/PREPARED>

#### Potential, to work with `go get`

You need:

  - generate a rsa key pairs, add public key into gitlab container.
  - add private key(mode 600) and public into client container.
  - edit .ssh/config in client container with GSSAPIAuthentication and StrictHostKeyChecking to no, like:

        host *
          GSSAPIAuthentication no
          StrictHostKeyChecking no

  - run `git config --global url."git@github.com:".insteadOf "https://github.com/"` in client container.

    **NOTE**, this will cause conflicts with git repo, as a result, when you try to clone a project not exist in gitlab, oneCache will fail to route request to github.
    So if you wan't this, you should get all projects you need into gitlab.
