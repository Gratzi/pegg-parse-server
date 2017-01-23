Slack = require 'slack-node'
slack = new Slack()
slack.setWebhook 'https://hooks.slack.com/services/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'

class Utils

  makeObject: (type, columns) =>
    obj = new Parse.Object type
    for own name, value of columns
      obj.set name, value
    obj

  # Report uncaught errors to Slack #errors
  slackError: (err, exit = false) =>
    # There are some errors we really don't care about. Filter them out.
    supressedCodes = (process.env.PEGG_SUPPRESS_ERROR_CODES or ' ')
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

module.exports = new Utils
