# FrontpageWatch2020


## For fun, not so much profit


### testing locally
```
# after installing the vapor app, cd into the project and run the folling (-t will post to reddit_api_test)
swift run Run query -u [my username] -p [my password] -c [reddit app id] -s [reddit app secret] -t true
```


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
swift run Run query

# push to heroku
echo 'web: Run serve --env production --hostname 0.0.0.0 --port $PORT' > Procfile
echo '5.1.2' > .swift-version
heroku create frontpagewatch2020
heroku buildpacks:set vapor/vapor
git commit -am "Update"
git push heroku master

# test 
heroku run Run query

# add postgress
https://docs.vapor.codes/3.0/fluent/getting-started/
brew install postgresql
brew services start postgresql
/usr/local/opt/postgres/bin/createuser -s postgres

# create a schema
    # create initial post model
    # create migration for initial post model
    # access model in command in future

# add postgress to heroku
heroku addons:create heroku-postgresql:hobby-dev
git commit -am "update"
git push # push to github
git push heroku master # deploy to heroku

# auth reddit
    # https://github.com/reddit-archive/reddit/wiki/oauth2
    # choose app type: https://github.com/reddit-archive/reddit/wiki/oauth2-app-types (i chose script)
    # quick start for script apps: https://github.com/reddit-archive/reddit/wiki/OAuth2-Quick-Start-Example

# local env
 - env vars are parsed from the command line or the env, run with --help for more info

 # heroku env
 heroku config:set REDDIT_USERNAME=my_username
 heroku config:set REDDIT_PASSWORD=my_password
 heroku config:set CLIENT_ID=client id
 heroku config:set REDDIT_SECRET=client secret

# call reddit
hurray

# save, diff
yep

# save diff

# post


# install the heroku scheduler https://devcenter.heroku.com/articles/scheduler
heroku addons:create scheduler:standard

```