Utils = require './utils'
debug = require 'debug'
log = debug 'pegg:worker:log'
errorLog = debug 'pegg:worker:error'
Slack = require './slack'

Promise = require('parse').Promise
Firebase = require 'firebase'
FirebaseTokenGenerator = require 'firebase-token-generator'
FIREBASE_SECRET = process.env.FIREBASE_SECRET or Slack.serverError "cannot have an empty FIREBASE_SECRET"
FIREBASE_DATABASE_URL = process.env.FIREBASE_DATABASE_URL or Slack.serverError "cannot have an empty FIREBASE_DATABASE_URL"

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
      inboxChannel.push { userId, type, timestamp }

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

  sendPush: ({ title, message, userId, friendId, type }) =>
    @_ready.then =>
      timestamp = Date.now()
      pushMessage =
        title: title
        message: message
        data:
          userId: userId
          friendId: friendId
          title: title
          message: message
          timestamp: timestamp
          style: "inbox"
          type: type
          summaryText: "%n% new messages"
      pushChannel = @_firebaseRef.child('push').child('tasks')
      pushChannel.push pushMessage

  getToken: ({ userId }) =>
    tokenGenerator = new FirebaseTokenGenerator FIREBASE_SECRET
    tokenGenerator.createToken {uid: userId}, {expires: 2272147200}

  getRef: =>
    @_ready.then =>
      @_firebaseRef

  getReady: =>
    @_ready

module.exports = new PeggFirebase
