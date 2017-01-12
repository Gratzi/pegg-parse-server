_ = require 'lodash'
debug = require 'debug'
log = debug 'pegg:fanOuts:log'
errorLog = debug 'pegg:fanOuts:error'
fail = (err) ->
  if typeof err is 'string'
    err = new Error err
  errorLog err
  throw err

Firebase = require '../lib/firebase'
Queue = require 'firebase-queue'
Promise = require('parse').Promise

class FanOutsWorker
  constructor: ->
    Firebase.getRef().then (firebase) =>
      @fanOutsChannel = firebase.child 'fanOuts'
      options =
        # Without a spec defined, spec defaults to:
        #
        # "default_spec": {
        #   "start_state": null,
        #   "in_progress_state": "in_progress",
        #   "finished_state": null,
        #   "error_state": "error",
        #   "timeout": 300000, // 5 minutes
        #   "retries": 0 // don't retry
        # }
        #
        # https://github.com/firebase/firebase-queue/blob/master/docs/guide.md#defining-specs-optional
        # specId: 'spec'
        # sanitize: false
        numWorkers: 5
      queue = new Queue @fanOutsChannel, options, @fanOut
      log "initialized"

  fanOut: (data, progress, resolve, reject) =>
    try
      log "fanning out friendsUpdate notifications", data
      Firebase.getRef().then (firebase) =>
        notified = for friendId in data.friendIds
          firebase.child("inbound/#{friendId}").push
            timestamp: data.timestamp
            type: 'friendsUpdate'
            userId: data.userId
        notified.push firebase.child("inbound/#{data.userId}").push
          timestamp: data.timestamp
          type: 'friendsUpdate'
          userId: data.friendId
        Promise.when notified
          .fail (error) =>
            reject error
            errorLog error
          .then => resolve()
    catch error
      errorLog "Error while receiving new message: ", error
      reject error

module.exports = FanOutsWorker
