#!/bin/bash

# 1. Navigate to the directory
cd "$MATRIX/hatch/stem" || { echo "Directory not found"; exit 1; }

# 2. Down the compose project only if it's running
# 'docker compose ps -q' returns nothing if no containers are active
if [ -n "$(docker compose ps -q)" ]; then
    echo "Stopping existing containers..."
    docker compose down
fi

# 3. Clean up specific volumes if they exist
VOLUMES=("home" "sshkeys" "sshstate")
for vol in "${VOLUMES[@]}"; do
    if docker volume inspect "$vol" >/dev/null 2>&1; then
        echo "Removing volume: $vol"
        docker volume rm "$vol"
    fi
done

# 4. Remove the image if it exists
if docker image inspect stem-stem:latest >/dev/null 2>&1; then
    echo "Removing old image..."
    docker rmi stem-stem:latest
fi

# 5. Re-create volumes
for vol in "${VOLUMES[@]}"; do
    docker volume create "$vol"
done

# 6. Rebuild and Launch
echo "Building and starting containers..."
docker compose build --no-cache stem
docker compose up -d
