#!/bin/bash -e

# the version to deploy is the one in package.json; raise it there
version=$(node -p "require('./package.json').version")
export repository=dummy

# run every test
npm test

# tag repository -> don't forget to run: git push --tags
git tag v$version

# build and push all variants
for tag in latest $version; do
    export tag
    docker compose build
    docker compose push
done

# deploy to kubernetes - or change the line to deploy elsewhere
kubectl set image deployment/bind bind=$repository/bind:$version
