Utils = require './utils'
debug = require 'debug'
log = debug 'pegg:worker:log'
errorLog = debug 'pegg:worker:error'
fail = (err) ->
  if typeof err is 'string'
    err = new Error err
  errorLog err
  Utils.slackError err

Promise = require('parse').Promise
Firebase = require 'firebase'
FirebaseTokenGenerator = require 'firebase-token-generator'
FIREBASE_SECRET = process.env.FIREBASE_SECRET or fail "cannot have an empty FIREBASE_SECRET"
FIREBASE_DATABASE_URL = process.env.FIREBASE_DATABASE_URL or fail "cannot have an empty FIREBASE_DATABASE_URL"

class PeggFirebase

  constructor: ->
    @_ready = new Promise
    @_firebaseRef = new Firebase FIREBASE_DATABASE_URL
    @_firebaseRef.authWithCustomToken FIREBASE_SECRET, (error, authData) =>
      if error?
        errorLog "Firebase login failed!", error
        @_ready.reject error
        fail error
      else
        log "Firebase login succeeded"
        @_ready.resolve()

  fanOut: ({ friendIds, userId, timestamp }) =>
    @_ready.then =>
      fanOutsChannel = @_firebaseRef.child 'fanOuts/tasks'
      fanOutsChannel.push { friendIds, userId, timestamp }

  getToken: ({ userId }) =>
    tokenGenerator = new FirebaseTokenGenerator FIREBASE_SECRET
    tokenGenerator.createToken {uid: userId}, {expires: 2272147200}

  getRef: =>
    @_ready.then =>
      @_firebaseRef

  getReady: =>
    @_ready

module.exports = new PeggFirebase

