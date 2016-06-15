_ = require 'lodash'
debug = require 'debug'
Firebase = require 'firebase'
Queue = require 'firebase-queue'
Promise = require('parse').Promise

log = debug 'fanOuts:log'
errorLog = debug 'fanOuts:error'
fail = (err) ->
  if typeof err is 'string'
    err = new Error err
  errorLog err
  throw err

FIREBASE_SECRET = process.env.FIREBASE_SECRET or fail "cannot have an empty FIREBASE_SECRET"
FIREBASE_DATABASE_URL = process.env.FIREBASE_DATABASE_URL or fail "cannot have an empty FIREBASE_DATABASE_URL"

fanOutsChannel = null

firebase = new Firebase FIREBASE_DATABASE_URL
firebase.authWithCustomToken FIREBASE_SECRET, (error, authData) =>
  if error?
    errorLog "Firebase login failed!", error
    throw error
  else
    log "logged into Firebase"
    fanOutsChannel = firebase.child 'fanOuts'
    options =
      # specId: 'spec'
      # sanitize: false
      numWorkers: 5
    queue = new Queue fanOutsChannel, options, fanOut

fanOut = (data, progress, resolve, reject) =>
  try
    log "fanning out friendsUpdate notifications", data
    notified = for friendId in data.friends
      firebase.child("inbound/#{friendId}").push
        timestamp: data.timestamp
        type: 'friendsUpdate'
        friendId: data.userId
    notified.push firebase.child("inbound/#{data.userId}").push
      timestamp: data.timestamp
      type: 'friendsUpdate'
    Promise.when notified
      .fail (error) =>
        reject error
        errorLog error
      .then => resolve()
  catch error
    errorLog "Error while receiving new message: ", error
    reject error
