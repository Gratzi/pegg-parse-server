# Example express application adding the parse-server module to expose Parse
# compatible API routes.
express = require('express')
ParseServer = require('parse-server').ParseServer
path = require('path')
databaseUri = process.env.DATABASE_URI or process.env.MONGODB_URI

if !databaseUri
  console.log 'DATABASE_URI not specified, falling back to localhost.'

api = new ParseServer(
  databaseURI: databaseUri or 'mongodb://localhost:27017/dev'
  cloud: process.env.CLOUD_CODE_MAIN or __dirname + '/cloud/main'
  appId: process.env.APP_ID or 'myAppId'
  masterKey: process.env.MASTER_KEY or ''
  serverURL: process.env.SERVER_URL or 'http://localhost:1337/parse'
  liveQuery: classNames: [
    'Posts'
    'Comments'
  ])

# Client-keys like the javascript key or the .NET key are not necessary with parse-server
# If you wish you require them, you can set them as options in the initialization above:
# javascriptKey, restAPIKey, dotNetKey, clientKey
app = express()

# Serve static assets from the /public folder
app.use '/public', express.static(path.join(__dirname, '/public'))

# Serve the Parse API on the /parse URL prefix
mountPath = process.env.PARSE_MOUNT or '/parse'
app.use mountPath, api

# Parse Server plays nicely with the rest of your web routes
app.get '/', (req, res) ->
  res.status(200).send 'I dream of being a website.  Please star the parse-server repo on GitHub!'

# There will be a test page available on the /test path of your server url
# Remove this before launching your app
app.get '/test', (req, res) ->
  res.sendFile path.join(__dirname, '/public/test.html')

port = process.env.PORT or 1337
httpServer = require('http').createServer(app)
httpServer.listen port, ->
  console.log 'parse-server-example running on port ' + port + '.'

# This will enable the Live Query real-time server
ParseServer.createLiveQueryServer httpServer