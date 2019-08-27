sleep 6
echo "selfCheck started..." >> /proc/1/fd/1
while true; do
    curl -sf http://0.0.0.0:8080/private.repo > /dev/null
    if [[ $? -ne 0 ]]; then
        kill -9 0
    fi
    sleep 3
done
