_ = require 'lodash'
PushNotifications = require 'node-pushnotifications'
debug = require 'debug'
Firebase = require 'firebase'
Queue = require 'firebase-queue'

log = debug 'pegg:push:log'
errorLog = debug 'pegg:push:error'
fail = (err) ->
  if typeof err is 'string'
    err = new Error err
  errorLog err
  throw err

FIREBASE_SECRET = process.env.FIREBASE_SECRET or fail "cannot have an empty FIREBASE_SECRET"
FIREBASE_DATABASE_URL = process.env.FIREBASE_DATABASE_URL or fail "cannot have an empty FIREBASE_DATABASE_URL"
GCM_API_KEY = process.env.GCM_API_KEY or fail "cannot have an empty GCM_API_KEY"
APN_CERT_PASSPHRASE = process.env.APN_CERT_PASSPHRASE or fail "cannot have an empty APN_CERT_PASSPHRASE"

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
      cert: "us.gratzi.pegg.pem"
      passphrase: APN_CERT_PASSPHRASE
    }
push = new PushNotifications pushSettings

pushChannel = null
registrationIdsChannel = null

firebase = new Firebase FIREBASE_DATABASE_URL
firebase.authWithCustomToken FIREBASE_SECRET, (error, authData) =>
  if error?
    console.error "Firebase login failed!", error
    throw error
  else
    registrationIdsChannel = firebase.child 'registrationIds'
    pushChannel = firebase.child 'push'
    options =
      specId: 'spec'
      sanitize: false
      numWorkers: 5
    queue = new Queue pushChannel, options, newMessage

newMessage = (notification, progress, resolve, reject) =>
  try
    receiver = notification.data.receiver
    if receiver?
      registrationIdsChannel.child(receiver).once 'value', (registrationsSnapshot) =>
        registrations = registrationsSnapshot.val()
        registrationIds = _.keys registrations
        if _.isEmpty registrationIds
          reject "no current device registrations"
          pushChannel.child('tasks').child(notification._id).remove()
        else
          sendPush registrationIds, notification, progress, resolve, reject
  catch error
    console.error "Error while receiving new message: ", error
    reject error

sendPush = (registrationIds, notification, progress, resolve, reject) ->
  try
    console.log "sending push: ", notification
    push.send registrationIds, notification, (error, result) ->
      if error?
        console.error error, { registrationIds }
        reject error
      else
        resolve()
  catch error
    console.error "Error while sending push: ", error
    reject error
