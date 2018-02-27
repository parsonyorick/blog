#! /usr/bin/env fish
cabal new-run blog -- --production
pushd _site.production
if count (git status --porcelain)
    git add .
    git commit
    git push
else
    echo Nothing new to deploy\!
end
popd
