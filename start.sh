#!/bin/bash
#
# Refer: https://security.stackexchange.com/questions/74345/provide-subjectaltname-to-openssl-directly-on-the-command-line
#        http://openssl.6102.n7.nabble.com/cmd-line-and-subjectAltName-td47538.html#a47548
#        http://wiki.cacert.org/FAQ/subjectAltName
#        https://serverfault.com/questions/647479/haproxy-use-backend-match-order
#        https://stackoverflow.com/questions/47094066/http-request-to-https-request-using-haproxy

#
# setup yum repo & file server
#
createrepo /var/www/html
cat > /var/www/html/private.repo << EOF
[private]
name=private
baseurl=http://`hostname -i`
enabled=1
gpgcheck=0
EOF
sed -i 's/^Listen 80$/Listen 8080/g' /etc/httpd/conf/httpd.conf
#httpd -DFOREGROUND
httpd


#
# setup haproxy to balance yum repo & file server between gitlab
#
# Generate private key
openssl genrsa -out ca.key 2048

# Generate CSR
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

# Generate Self Signed Key
openssl x509 -req -days 365 -in ca.csr -signkey ca.key -out ca.crt

# Generate .pem
cat ca.crt ca.key > ca.pem

# get file server acl path_beg
repo_path_begs=""
lastline=""
for i in `ls -R /var/www/html/ | egrep "^/" | sort -r`; do
    if [[ $i == "/var/www/html/repodata:" || $i == "/var/www/html/:" ]]; then
        continue
    fi
    if [[ $lastline != "" ]]; then
        echo $i | grep -q $lastline
        if [[ $? -ne 0 ]]; then
            repo_path_begs="$repo_path_begs /$lastline/"
        fi
    fi
    lastline=`echo $i | cut -d '/' -f 5- | cut -d ':' -f 1`
done
repo_path_begs="$repo_path_begs /$lastline/"

# get projects proxied by gitlab
git_path_begs=""
while IFS='' read -r line || [[ -n "$line" ]]; do
    if [[ $line == "" || ${line:0:1} == "#" ]]; then
        continue
    fi
    groupProj=`echo $line | awk '{print $2}'`
    if [[ $groupProj == "-" ]]; then
        groupProj=`echo $line | awk '{print $3}' | cut -d '/' -f 4-5 | cut -d '.' -f 1`
    fi
    git_path_begs="$git_path_begs /$groupProj"
done < /gitlab_projects/Manifests


# modify haproxy.cfg
sed -i '/\sdaemon$/atune.ssl.default-dh-param  2048' /etc/haproxy/haproxy.cfg
sed -i 's/\sdaemon$/ #daemon/g' /etc/haproxy/haproxy.cfg
sed -i '/^frontend/,$d' /etc/haproxy/haproxy.cfg
cat >> /etc/haproxy/haproxy.cfg << EOF
frontend main
    bind :443 ssl crt /ca.pem
    default_backend default_be

backend default_be
EOF
if [[ $GITLAB_IP != "" ]]; then
cat >> /etc/haproxy/haproxy.cfg << EOF
    acl use_repo   path_beg $repo_path_begs
    acl use_gitlab path_beg $git_path_begs
    acl use_gitlab hdr_beg(host) -m beg gitlab.
    acl use_github hdr_beg(host) -m beg github.

    http-request set-header X-Forwarded-Protocol https if use_gitlab
    http-request set-header X-Forwarded-Proto https    if use_gitlab
    http-request set-header X-Forwarded-Ssl on         if use_gitlab
    http-request set-header X-Url-Scheme https         if use_gitlab

    use-server repo if use_repo
    server     repo 127.0.0.1:8080 check weight 0

    use-server github if use_github !use_gitlab
    server     github github.com:443 ssl verify none

    use-server gitlab if use_gitlab
    server     gitlab $GITLAB_IP:80 check weight 0

EOF
fi
cat >> /etc/haproxy/haproxy.cfg << EOF
    server     default 127.0.0.1:8080 check

listen tcp80
    bind :80
    server local 127.0.0.1:8080 check
EOF
haproxy -f /etc/haproxy/haproxy.cfg -c

# setup a loop process to check and populate projects
if [[ $GITLAB_IP != "" && $POP_PROJECTS == "true" ]]; then
    nohup sleep 3 && ./popPorjects.sh &
fi
haproxy -f /etc/haproxy/haproxy.cfg
