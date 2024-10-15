#!/bin/bash

export IMAGE_VARIANT=cuda-12.1.0-ubuntu22.04 

export DOCKER_PROJECT_ID=kmu 
bash .docker/.docker-scripts/docker-compose.sh up --detach

export DOCKER_PROJECT_ID=est 
bash .docker/.docker-scripts/docker-compose.sh up --detach
