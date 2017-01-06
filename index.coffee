require('dotenv').config()

# Report uncaught errors to Slack #errors
Slack = require 'slack-node'
slack = new Slack()
slack.setWebhook 'https://hooks.slack.com/services/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'

uncaughtException = (err, exit = false) =>
  # There are some errors we really don't care about. Filter them out.
  supressedCodes = PEGG_SUPPRESS_ERROR_CODES
    .split ','
    .map (code) => parseInt code
  return if supressedCodes.includes err.code

  logMessage = if err.stack? then err.stack else JSON.stringify err
  console.error "OMG uncaught internal server error.", logMessage
  slack.webhook
    channel: "#errors"
    username: 'PeggErrorBot'
    icon_emoji: ":ghost:"
    title: "Parse Server Critical Error"
    text: "```#{logMessage}```"
  , (err, response) =>
    if err? then console.error "Error posting error to Slack #errors. Fail sauce.", err
    if exit then process.exit 1

try
  require 'newrelic'
  express = require 'express'
  path = require 'path'
  ParseServer = require('parse-server').ParseServer

  # Set up Parse server
  databaseUri = process.env.DATABASE_URI or process.env.MONGODB_URI

  if !databaseUri
    console.log 'DATABASE_URI not specified, falling back to localhost.'

  api = new ParseServer(
    databaseURI: databaseUri or 'mongodb://localhost:27017/dev'
    cloud: process.env.CLOUD_CODE_MAIN or __dirname + '/cloud/main'
    appId: process.env.APP_ID or 'myAppId'
    masterKey: process.env.MASTER_KEY or ''
    serverURL: process.env.SERVER_URL or 'http://localhost:1337/parse'
    # liveQuery: classNames: [
    #   'Posts'
    #   'Comments'
    # ]
  )

  # Use old-style (jQuery style) Parse promises
  Parse.Promise.disableAPlusCompliant()

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
    res.status(200).send 'Nothing to see here, move along...'

  # # There will be a test page available on the /test path of your server url
  # # Remove this before launching your app
  # app.get '/test', (req, res) ->
  #   res.sendFile path.join(__dirname, '/public/test.html')

  # Report uncaught errors to Slack #errors
  # NOTE: This must come last or it won't work.
  app.use (err, req, res, next) =>
    if err? then uncaughtException err

  port = process.env.PORT or 1337
  httpServer = require('http').createServer(app)
  httpServer.listen port, ->
    console.log 'pegg-parse-server running on port ' + port + '.'

  # This will enable the Live Query real-time server
  ParseServer.createLiveQueryServer httpServer
catch err
  uncaughtException err, true
