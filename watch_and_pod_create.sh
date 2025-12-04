#!/bin/bash
# watch_and_create.sh

WORKSPACES_DIR="/mnt/test-k8s/workspaces"

echo "Starting to watch workspaces directory: $WORKSPACES_DIR"
echo "Monitoring for scheduling field additions in job spec files..."

inotifywait -m -r -e modify,close_write --format '%w%f' "$WORKSPACES_DIR" | while read CHANGED_FILE
do
    # job-{TYPE}-{ID}[-{INDEX}].yaml 형식만 처리
    # std, grad, prof: job-TYPE-ID.yaml
    # cls: job-cls-ID-INDEX.yaml (INDEX는 숫자)
    if [[ "$CHANGED_FILE" =~ job-(std|grad|prof)-[a-zA-Z0-9]+\.yaml$ ]] || \
       [[ "$CHANGED_FILE" =~ job-cls-[a-zA-Z0-9]+-[0-9]+\.yaml$ ]]; then
        echo "Detected change in: $CHANGED_FILE"

        # job spec 파일인지 내용으로 한번 더 확인
        if ! yq eval 'has("user") and has("job")' "$CHANGED_FILE" 2>/dev/null | grep -q "true"; then
            echo "Not a valid job spec file. Skipping..."
            continue
        fi

        # scheduling 필드가 존재하는지 확인
        if yq eval 'has("scheduling")' "$CHANGED_FILE" 2>/dev/null | grep -q "true"; then
            echo "Scheduling field found in $CHANGED_FILE"

            PROCESSED_MARKER="${CHANGED_FILE}.processed"
            if [ -f "$PROCESSED_MARKER" ]; then
                echo "Already processed. Skipping..."
                continue
            fi

            echo "Creating Kubernetes resources..."
            if create_k8s_resources.sh "$CHANGED_FILE"; then
                touch "$PROCESSED_MARKER"
                echo "Successfully created resources for $CHANGED_FILE"
            else
                echo "Failed to create resources for $CHANGED_FILE"
            fi
        fi
    fi
done