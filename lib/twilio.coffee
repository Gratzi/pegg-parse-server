twilio = require 'twilio'
Promise = require('parse').Promise
debug = require 'debug'
log = debug 'pegg:worker:log'
errorLog = debug 'pegg:worker:error'
client = null

TWILIO_SID = process.env.TWILIO_SID or fail "cannot have an empty TWILIO_SID"
TWILIO_SECRET = process.env.TWILIO_SECRET or fail "cannot have an empty TWILIO_SECRET"
TWILIO_NUMBER = process.env.TWILIO_NUMBER or fail "cannot have an empty TWILIO_NUMBER"

class PeggTwilio

  constructor: ->
    log "Initializing Twilio..."
    client = new twilio(TWILIO_SID, TWILIO_SECRET)

  sendSMS: (toNumber, body) =>
    client.messages.create
      from: TWILIO_NUMBER
      to: toNumber
      body: body

module.exports = new PeggTwilio
