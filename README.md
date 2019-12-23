# FrontpageWatch2020


## For fun, not so much profit




### How I built this

# Step by step instructions

```
# install or update vapor
brew install vapor
brew upgrade vapor

# create a vapor project using clean template
vapor new MyProject --template=twostraws/vapor-clean
cd MyProject
vapor xcode

# add remote to github repo 
git remote add origin git@github.com:myusername/myreponame.git
git push -u origin master

# create a command
# https://docs.vapor.codes/3.0/command/overview/

# push to heroku
echo 'web: Run serve --env production --hostname 0.0.0.0 --port $PORT' > Procfile
echo '5.1.2' > .swift-version
heroku create frontpagewatch2020
heroku buildpacks:set vapor/vapor
git commit -am "Update"
git push heroku master

# add postgress

# create a schema




# install the heroku scheduler https://devcenter.heroku.com/articles/scheduler
heroku addons:create scheduler:standard

```