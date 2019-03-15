#!/bin/bash
#
# Refer: https://security.stackexchange.com/questions/74345/provide-subjectaltname-to-openssl-directly-on-the-command-line
#        http://openssl.6102.n7.nabble.com/cmd-line-and-subjectAltName-td47538.html#a47548
#        http://wiki.cacert.org/FAQ/subjectAltName
#        https://serverfault.com/questions/647479/haproxy-use-backend-match-order
#        https://stackoverflow.com/questions/47094066/http-request-to-https-request-using-haproxy


function setup_repo(){
    createrepo /var/www/html
    cat > /var/www/html/private.repo << EOF
[private]
name=private
baseurl=http://`hostname -i`
enabled=1
gpgcheck=0
EOF
    sed -i 's/^Listen 80$/Listen 8080/g' /etc/httpd/conf/httpd.conf
    httpd
}


function gen_certs(){
    openssl genrsa -out ca.key 2048

    cat > /etc/ssl/openssl-san.cnf << EOF
[req]
default_bits = 2048
prompt = no
default_md = sha1
req_extensions = req_ext
distinguished_name = dn
[ dn ]
CN = example.com
[ req_ext ]
subjectAltName = IP:`hostname -i`
EOF

    country="/countryName=CN"
    state="/stateOrProvinceName=Beijing"
    locality="/localityName=Beijing"
    org="/organizationName=nihao"
    orgUnit="/organizationalUnitName=world"
    common="/commonName=test"
    subj="$country$state$locality$org$orgUnit$common"

    openssl req -subj $subj -new -config /etc/ssl/openssl-san.cnf -new -key ca.key -out ca.csr

    openssl x509 -req -days 365 -in ca.csr -signkey ca.key -out ca.crt

    cat ca.crt ca.key > /ca.pem
}


function get_download_path_begs(){
    dl_path_begs=""
    lastline=""
    for i in `ls -R /var/www/html/ | egrep "^/" | sort -r`; do
        if [[ $i == "/var/www/html/repodata:" || $i == "/var/www/html/:" ]]; then
            continue
        fi
        if [[ $lastline != "" ]]; then
            echo $i | grep -q $lastline
            if [[ $? -ne 0 ]]; then
                dl_path_begs="$dl_path_begs /$lastline/"
            fi
        fi
        lastline=`echo $i | cut -d '/' -f 5- | cut -d ':' -f 1`
    done
    if [[ $dl_path_begs == "" ]]; then
        echo "/NO_DOWNLOAD_FOUND"
    else
        dl_path_begs="$dl_path_begs /$lastline/"
        echo $dl_path_begs
    fi
}


function get_git_path_begs(){
    git_path_begs=""
    while IFS='' read -r line || [[ -n "$line" ]]; do
        line=`echo $line | tr -d "\n"`
        if [[ $line == "" || ${line:0:1} == "#" ]]; then
            continue
        fi
        groupProj=`echo $line | awk '{print $2}'`
        if [[ $groupProj == "-" ]]; then
            groupProj=`echo $line | awk '{print $3}' | cut -d '/' -f 4-5 | cut -d '.' -f 1`
        fi
        git_path_begs="$git_path_begs /$groupProj"
    done < /gitlab_projects/Manifests
    if [[ $git_path_begs == "" ]]; then
        echo "/NO_GIT_REPO_FOUND"
    else
        echo $git_path_begs
    fi
}


function haproxy_cfg_prepare(){
    sed -i '/\sdaemon$/atune.ssl.default-dh-param  2048' /etc/haproxy/haproxy.cfg
    sed -i 's/\sdaemon$/ #daemon/g' /etc/haproxy/haproxy.cfg
    sed -i '/^frontend/,$d' /etc/haproxy/haproxy.cfg

    cat >> /etc/haproxy/haproxy.cfg << EOF
listen tcp80
    bind :80
    server local 127.0.0.1:8080 check

frontend main
    bind :443 ssl crt /ca.pem
    default_backend default_be

EOF
}


function haproxy_cfg_complete(){
    dl_path_begs=`get_download_path_begs`
    git_path_begs=`get_git_path_begs`
    if [[ $GITLAB_IP == "" ]]; then
        cat >> /etc/haproxy/haproxy.cfg << EOF
backend default_be
    server     default 127.0.0.1:8080 check
EOF
    else
        cat >> /etc/haproxy/haproxy.cfg << EOF
backend default_be
    acl use_dl     path_beg $dl_path_begs
    acl use_gitlab path_beg $git_path_begs
    acl use_gitlab hdr_beg(host) -m beg gitlab.
    acl use_github hdr_beg(host) -m beg github.

    http-request set-header X-Forwarded-Protocol https if use_gitlab
    http-request set-header X-Forwarded-Proto https    if use_gitlab
    http-request set-header X-Forwarded-Ssl on         if use_gitlab
    http-request set-header X-Url-Scheme https         if use_gitlab

    use-server dl_svc if use_dl
    server     dl_svc 127.0.0.1:8080 check weight 0

    use-server github if use_github !use_gitlab
    server     github github.com:443 ssl verify none

    use-server gitlab if use_gitlab
    server     gitlab $GITLAB_IP:80 check weight 0

    server     default 127.0.0.1:8080 check

listen tcp22
    bind :22
    mode tcp
    server gitlab $GITLAB_IP:22 check

EOF
    fi
}


function start_popProject(){
    if [[ $GITLAB_IP != "" && $POP_PROJECTS == "true" ]]; then
        nohup sleep 3 && ./popPorjects.sh &
    fi
}


function main(){
    setup_repo
    gen_certs
    haproxy_cfg_prepare
    haproxy_cfg_complete
    haproxy -f /etc/haproxy/haproxy.cfg -c
    start_popProject
    haproxy -f /etc/haproxy/haproxy.cfg
}


main
