debug = require 'debug'
log = debug 'pegg:worker:log'
errorLog = debug 'pegg:worker:error'
fail = (err) ->
  if typeof err is 'string'
    err = new Error err
  errorLog err
  throw err

Firebase = require '../lib/firebase'
PushWorker = require './push'
FanOutsWorker = require './fanOuts'

push = new PushWorker()
fanOuts = new FanOutsWorker()
