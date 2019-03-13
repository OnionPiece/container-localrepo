#!/bin/bash
#
# Refer: https://stackoverflow.com/questions/10929453/read-a-file-line-by-line-assigning-the-value-to-a-variable

echo "127.0.0.1  gitlab.local.io" >> /etc/hosts
git config --global user.email "you@example.com"
git config --global user.name "Your Name"
git config --global http.sslVerify false

gitlab="gitlab.local.io"
url="https://$gitlab/api/v4"
while true; do
    while IFS='' read -r line || [[ -n "$line" ]]; do
        if [[ $line == "" || ${line:0:1} == "#" ]]; then
            continue
        fi
        folder=`echo $line | awk '{print $1}'`
        groupProj=`echo $line | awk '{print $2}'`
        if [[ $groupProj == "-" ]]; then
            groupProj=`echo $line | awk '{print $3}' | cut -d '/' -f 4-5 | cut -d '.' -f 1`
        fi
        group=`echo $groupProj | cut -d '/' -f 1`
        project=`echo $groupProj | cut -d '/' -f 2`

        curl -s -k $url/projects | grep -q $gitlab/$groupProj
        if [[ $? -eq 0 ]]; then
            continue
        fi
        # process
        namespace_id=`curl -s -H "Private-Token: $PRIVATE_TOKEN" -H "Content-Type: application/json" -k -X POST $url/groups -d '{"name":"'$group'", "path":"'$group'", "visibility":"public", "lfs_enabled":true, "parent_id": null}' | python -mjson.tool | awk '/"id"/{print $2}' | cut -d ',' -f 1`
        curl -H "Private-Token: $PRIVATE_TOKEN" -H "Content-Type: application/json" -k -X POST $url/projects -d '{"name":"'$project'", "path":"'$project'", "namespace_id": '$namespace_id', "default_branch": "master", "visibility":"public", "lfs_enabled":true}'
        project_id=`curl -s -H "Private-Token: d6T5bNvoPU_6WfdodCLr" -H "Content-Type: application/json" -k $url/groups/$namespace_id/projects | python -mjson.tool | awk -F'/' '/"events"/{print $7}'`
        # for case project is not public
        curl -k -H "Private-Token: $PRIVATE_TOKEN" -H "Content-Type: application/json" -X PUT https://gitlab.local.io/api/v4/projects/$project_id -d '{"visibility":"public"}'
        pushd /gitlab_projects/$folder
        rm -rf .git
        git init
        git remote add origin https://$GIT_USER:$GIT_PASS@$gitlab/$groupProj.git
        git add .
        git commit -m 'init'
        git push -u origin master
        popd
        sleep 1
    done < /gitlab_projects/Manifests
    sleep 15
done
