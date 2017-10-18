SLACK_URL = process.env.SLACK_URL or throw new Error "cannot have an empty SLACK_URL"
PEGG_SUPPRESS_ERROR_CODES = process.env.PEGG_SUPPRESS_ERROR_CODES or ' '
Slack = require 'slack-node'
slack = new Slack()
slack.setWebhook SLACK_URL
debug = require 'debug'
errorLog = debug 'pegg:worker:error'

Slack =

  # Report uncaught errors to Slack #errors
  serverError: (err, exit = false) =>
    # There are some errors we really don't care about. Filter them out.
    supressedCodes = (PEGG_SUPPRESS_ERROR_CODES or ' ')
      .split ','
      .map (code) => parseInt code
    return if supressedCodes.includes err.code

    logMessage = if err.stack? then err.stack else JSON.stringify err

    errorLog err "OMG uncaught internal server error.", logMessage
    slack.webhook
      channel: "#errors"
      username: 'PeggErrorBot'
      icon_emoji: ":ghost:"
      title: "Parse Server Critical Error"
      text: "```#{logMessage}```"
    , (err, response) =>
      if err? then console.error "Error posting server error to Slack #errors. Fail sauce.", err
      if exit then process.exit 1

  # Report client-side errors to Slack #errors
  clientError: (err, user, userAgent) =>
    promise = new Parse.Promise()
    logMessage = if err.stack? then err.stack else JSON.stringify err
    slack.webhook
      channel: "#errors"
      username: 'PeggErrorBot'
      icon_emoji: ":ghost:"
      text: """
        *User*: #{user.name} (#{user.id})
        *UserAgent*: #{userAgent}
        ```#{err.message}```
        ```#{err.stack}```
      """
    , (err, response) =>
      if err?
        errorLog err "Error posting client error to Slack #errors. Fail sauce.", err
        promise.reject err
      else
        promise.resolve response
    promise

  # Report user feedback to Slack #feedback
  userFeedback: (user, userAgent, context, feedback) =>
    promise = new Parse.Promise()
    slack.webhook
      channel: '#feedback'
      username: user.name
      icon_emoji: ':unicorn_face:'
      text: """
        *UserId*: #{user.id}
        *Email*: #{user.email}
        *UserAgent*: #{userAgent}
        *Context*: #{context}
        ```#{feedback}```
      """
    , (err, response) =>
      if err?
        console.error "Error posting feedback to Slack #errors. Fail sauce.", err
        promise.reject err
      else
        promise.resolve response
    promise

module.exports = Slack
