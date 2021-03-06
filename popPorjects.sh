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

        groupId=`curl -s -k -H "Private-Token: $PRIVATE_TOKEN" -H "Content-Type: application/json" $url/groups?search=$group | python -mjson.tool | awk '/"id"/{print $2}' | cut -d ',' -f 1`
        if [[ $groupId == "" ]]; then
            groupId=`curl -s -k -H "Private-Token: $PRIVATE_TOKEN" -H "Content-Type: application/json" -X POST $url/groups -d '{"name":"'$group'", "path":"'$group'", "visibility":"public", "lfs_enabled":true, "parent_id": null, "request_access_enabled":true}' | python -mjson.tool | awk '/"id"/{print $2}' | cut -d ',' -f 1`
            sleep 2
        fi

        curl -s -k -H "Private-Token: $PRIVATE_TOKEN" -H "Content-Type: application/json" $url/groups/$groupId/projects | python -mjson.tool | grep "name\": \"$project\"" > /dev/null
        if [[ $? -eq 0 ]]; then
            continue
        fi

        echo "Found project $group/$project not populated into gitlab.local.io"
        projectId=`curl -s -H "Private-Token: $PRIVATE_TOKEN" -H "Content-Type: application/json" -k -X POST $url/projects -d '{"name":"'$project'", "path":"'$project'", "namespace_id": '$groupId', "default_branch": "master", "visibility":"public", "lfs_enabled":true, "request_access_enabled":true}' | python -mjson.tool | awk -F'/' '/"events"/{print $7}'`
        sleep 1

        attrCheckRes=`curl -s -k -H "Private-Token: $PRIVATE_TOKEN" -H "Content-Type: application/json" $url/projects/$projectId | python -mjson.tool | egrep "(\"visibility\": \"public\"|\"request_access_enabled\": true)" | wc -l`
        if [[ $attrCheckRes -ne 2 ]]; then
            curl -s -k -H "Private-Token: $PRIVATE_TOKEN" -H "Content-Type: application/json" -X PUT $url/projects/$projectId -d '{"visibility":"public", "request_access_enabled":"true"}' > /dev/null
            sleep 1
        fi

        pushd /gitlab_projects/$folder > /dev/null
        git remote remove origin
        git remote add origin https://$GIT_USER:$GIT_PASS@$gitlab/$group/$project.git
        git push --set-upstream origin master
        git push --tags
        popd > /dev/null
        sleep 1
    done < /gitlab_projects/Manifests
    sleep 15
done
