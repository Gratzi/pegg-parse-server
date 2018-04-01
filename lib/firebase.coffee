Utils = require './utils'
debug = require 'debug'
log = debug 'pegg:worker:log'
errorLog = debug 'pegg:worker:error'
Slack = require './slack'

Promise = require('parse').Promise
Firebase = require 'firebase'
admin = require 'firebase-admin'
FIREBASE_SECRET = process.env.FIREBASE_SECRET or Slack.serverError "cannot have an empty FIREBASE_SECRET"
FIREBASE_DATABASE_URL = process.env.FIREBASE_DATABASE_URL or Slack.serverError "cannot have an empty FIREBASE_DATABASE_URL"
FIREBASE_SERVICE_ACCOUNT = process.env.FIREBASE_SERVICE_ACCOUNT or Slack.serverError "cannot have an empty FIREBASE_SERVICE_ACCOUNT"
admin.initializeApp({
  credential: admin.credential.cert(JSON.parse FIREBASE_SERVICE_ACCOUNT),
  databaseURL: FIREBASE_DATABASE_URL
})

class PeggFirebase

  constructor: ->
    log "Initializing Firebase..."
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

  sendToInbox: ({ friendId, userId, type }) =>
    @_ready.then =>
      timestamp = Date.now()
      log "sending to Inbox: ", friendId, userId, type, timestamp
      inboxChannel = @_firebaseRef.child "inbound/#{friendId}"
      inboxChannel.push { userId, friendId, type, timestamp }

  saveVerifyCode: ({ phoneNumber, code }) =>
    @_ready.then =>
      log "saving code: ", phoneNumber
      promise = new Promise
      inboxChannel = @_firebaseRef.child "verify/#{phoneNumber}"
      inboxChannel.set code, (error) =>
        if error?
          log.error "writing verifyCode failed", error
          promise.reject error
        else
          promise.resolve()

  getVerifyCode: ({ phoneNumber }) =>
    @_ready.then =>
      promise = new Promise
      verifyChannel = @_firebaseRef.child "verify/#{phoneNumber}"
      verifyChannel.once 'value', (snapshot) =>
        if snapshot?
          promise.resolve snapshot.val()
        else
          promise.reject()
      promise

  sendPush: (payload) =>
    @_ready.then =>
      timestamp = Date.now()
      pushChannel = @_firebaseRef.child('push')
      pushChannel.push payload

  getToken: ({ userId }) =>
    # tokenGenerator = new FirebaseTokenGenerator FIREBASE_SECRET
    # tokenGenerator.createToken {uid: userId}, {expires: 2272147200}
    promise = new Promise
    admin.auth().createCustomToken(userId).then((customToken) ->
      # Send token back to client
      promise.resolve customToken
    ).catch (error) ->
      log.error 'Error creating custom token:', error
      promise.reject error
    return promise

  getRef: =>
    @_ready.then =>
      @_firebaseRef

  getReady: =>
    @_ready

module.exports = new PeggFirebase
