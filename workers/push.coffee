_ = require 'lodash'
debug = require 'debug'
log = debug 'pegg:push:log'
errorLog = debug 'pegg:push:error'
fail = (err) ->
  if typeof err is 'string'
    err = new Error err
  errorLog err
  throw err

PushNotifications = require 'node-pushnotifications'
Queue = require 'firebase-queue'

GCM_API_KEY = process.env.GCM_API_KEY or fail "cannot have an empty GCM_API_KEY"
APN_CERT_PASSPHRASE = process.env.APN_CERT_PASSPHRASE or fail "cannot have an empty APN_CERT_PASSPHRASE"
APN_PEM = process.env.APN_PEM or fail "cannot have an empty APN_PEM"

pushSettings =
  gcm:
    id: GCM_API_KEY
    msgcnt: 1
    dataDefaults:
      delayWhileIdle: false
      timeToLive: 4 * 7 * 24 * 3600
      retries: 4
    options: {}
  apn:
    gateway: 'gateway.sandbox.push.apple.com'
    badge: 1
    defaultData:
      expiry: 4 * 7 * 24 * 3600
      sound: 'ping.aiff'
    options: {
      cert: APN_PEM
      passphrase: APN_CERT_PASSPHRASE
    }

class PushWorker
  constructor: (@firebase) ->
    @push = new PushNotifications pushSettings
    @registrationIdsChannel = @firebase.child 'registrationIds'
    @pushChannel = @firebase.child 'push'
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
      sanitize: false
      numWorkers: 5
    queue = new Queue @pushChannel, options, @newMessage
    log "initialized"

  newMessage: (notification, progress, resolve, reject) =>
    # log "new message received", notification
    try
      receiver = notification.data.receiver
      if receiver?
        @registrationIdsChannel.child(receiver).once 'value', (registrationsSnapshot) =>
          registrations = registrationsSnapshot.val()
          registrationIds = _.keys registrations
          if _.isEmpty registrationIds
            reject "no current device registrations"
            @pushChannel.child('tasks').child(notification._id).remove()
          else
            @sendPush registrationIds, notification, progress, resolve, reject
    catch error
      errorLog "Error while receiving new message: ", error
      reject JSON.stringify error

  sendPush: (registrationIds, notification, progress, resolve, reject) ->
    try
      log "sending push: ", notification
      @push.send registrationIds, notification, (error, result) ->
        if error?
          errorLog error, { registrationIds }
          reject JSON.stringify error
        else
          resolve()
    catch error
      errorLog "Error while sending push: ", error
      reject JSON.stringify error

module.exports = PushWorker
