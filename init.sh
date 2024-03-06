#!/bin/sh
TOKEN=$(cat /gitlab-secret/token)
SECRET_THRESHOLD=3
SECRET_SHARES=5
GITLAB_PROJECT_URL="$GITLAB_API_URL/projects/$GITLAB_PROJECT_ID"
while true; do 
    cd ~/
    # Check Vault Status 
    curl -s http://127.0.0.1:8200/v1/sys/seal-status > status.json
    if (grep -q '"initialized":false' status.json)
    then
        echo "$(date) Uninitialized"
        if (hostname | grep -q ".*-0")
        then                                                    #Intialize cluster leader only
            echo "$(date) Leader... Initializing" 
            curl -s --request POST --data "{\"secret_shares\": $SECRET_SHARES, \"secret_threshold\": $SECRET_THRESHOLD}" http://127.0.0.1:8200/v1/sys/init > keys.json
            echo "$(date) Replace GitLab variable's content " 
            curl -s --globoff --request DELETE --insecure --header "PRIVATE-TOKEN: $TOKEN" "$GITLAB_PROJECT_URL/variables/$GITLAB_VARIABLE_NAME?filter[environment_scope]=$GITLAB_ENV_SCOPE"  > /dev/null && true
            curl -s --globoff --request POST --insecure --header "PRIVATE-TOKEN: $TOKEN" "$GITLAB_PROJECT_URL/variables" --form "key=$GITLAB_VARIABLE_NAME" --form "value=$(cat keys.json | base64 | tr -d \\n)" --form "environment_scope=$GITLAB_ENV_SCOPE" > /dev/null
            echo "$(date) Initialized"
            # Check Vault Status 
            curl -s http://127.0.0.1:8200/v1/sys/seal-status > status.json
        else
            echo "$(date) Joining  leader"                           #Otherwise just wait until connected to the cluster
            curl -s --request POST --data "{\"leader_api_addr\": \"http://vault-0.vault-internal:8200\"}" http://127.0.0.1:8200/sys/storage/raft/join
            curl -s http://127.0.0.1:8200/v1/sys/seal-status > status.json
        fi 
    fi  

    if (grep -q '"initialized":true' status.json) && (grep -q '"sealed":true' status.json)
    then 
        echo "$(date) Unsealing"
        count=1       

        if [ ! -f keys.json ]
        then 
            echo "$(date) Getting unsealing keys"
            curl -s --request GET --insecure --globoff --header "PRIVATE-TOKEN: $TOKEN" "$GITLAB_PROJECT_URL/variables/$GITLAB_VARIABLE_NAME?filter[environment_scope]=$GITLAB_ENV_SCOPE" > response.json
            sed "s/.*\"key\":\"$GITLAB_VARIABLE_NAME\",\"value\":\(.*\),\"protected\".*/\1/" response.json | base64 -d > keys.json
            echo "$(date) Unsealing keys received"
        fi 
        
        while [ $count -le $SECRET_THRESHOLD ]
        do
            echo "$(date) Unsealing step $count"
            key=$(sed 's/{"keys":\[\(.*\)\].*"keys_base.*/\1/' keys.json| tr -d '"' | cut -d',' -f$count)
            let count=count+1
            # Vault unsealing
            curl -s --request POST --data "{\"key\": \"$key\"}" http://127.0.0.1:8200/v1/sys/unseal > status.json
            cat status.json
            sleep 10 #important to give vault some time to react on unsealing
        done
        echo "$(date) Unsealed"
        rm *.json
    fi
    sleep 60
done    