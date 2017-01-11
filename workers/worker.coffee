debug = require 'debug'
log = debug 'pegg:worker:log'
errorLog = debug 'pegg:worker:error'
fail = (err) ->
  if typeof err is 'string'
    err = new Error err
  errorLog err
  throw err

PushWorker = require './push'
FanOutsWorker = require './fanOuts'
Firebase = require '../lib/firebase'

push = new PushWorker()
fanOuts = new FanOutsWorker()
