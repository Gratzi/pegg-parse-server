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
Firebase = require 'firebase'

FIREBASE_SECRET = process.env.FIREBASE_SECRET or fail "cannot have an empty FIREBASE_SECRET"
FIREBASE_DATABASE_URL = process.env.FIREBASE_DATABASE_URL or fail "cannot have an empty FIREBASE_DATABASE_URL"

firebase = new Firebase FIREBASE_DATABASE_URL
firebase.authWithCustomToken FIREBASE_SECRET, (error, authData) =>
  if error?
    errorLog "Firebase login failed!", error
    throw error
  else
    log "firebase login succeeded"
    push = new PushWorker firebase
    fanOuts = new FanOutsWorker firebase
