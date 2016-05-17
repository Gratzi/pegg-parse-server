FIREBASE_URL = 'https://pegg-staging.firebaseio.com/'
PEGG_FIREBASE_URL = 'https://pegg-firebase-staging.herokuapp.com'
FIREBASE_SECRET = null
PEGG_SECRET = null

Firebase =
  initialize: =>
    unless FIREBASE_SECRET?
      Parse.Config.get().then (config) =>
        FIREBASE_SECRET = config.get 'firebaseSecret'
        PEGG_SECRET = config.get 'peggSecret'
        FIREBASE_URL = config.get 'firebaseUrl'
        PEGG_FIREBASE_URL = config.get 'peggFirebaseUrl'

#  saveNewCard: (cardId, userId, friends, createdAt) =>
#    Firebase.initialize().then =>
#      data =
#        secret: PEGG_SECRET
#        userId: userId
#        cardId: cardId
#        friends: friends
#        timestamp: createdAt
#        success: (res) => console.log "FIREBASE::saveCard: SUCCESS --- #{JSON.stringify res}"
#        error: (err) => console.error "FIREBASE::saveCard: ERROR! OMG. --- #{JSON.stringify err}"
#      req =
#        method: "POST"
#        url: "#{PEGG_FIREBASE_URL}/newCard"
#        headers:
#          'Content-Type': 'application/json'
#        body: JSON.stringify data
#      console.log "FIREBASE::saveCard request --- #{JSON.stringify req, null, 2}"
#      Parse.Cloud.httpRequest req

  saveNewUser: (userId, friends, createdAt) =>
    Firebase.initialize().then =>
      data =
        secret: PEGG_SECRET
        userId: userId
        timestamp: createdAt.valueOf()
        friends: friends
        success: (res) => console.log "FIREBASE::saveNewUser: SUCCESS --- #{JSON.stringify res}"
        error: (err) => console.error "FIREBASE::saveNewUser: ERROR! OMG. --- #{JSON.stringify err}"
      req =
        method: "POST"
        url: "#{PEGG_FIREBASE_URL}/newUser"
        headers:
          'Content-Type': 'application/json'
        body: JSON.stringify data
      console.log "FIREBASE::saveNewUser request --- #{JSON.stringify req, null, 2}"
      Parse.Cloud.httpRequest req

#  savePegg: (peggId, peggeeId, userId, prefId, tryCount, updatedAt) =>
#    Firebase.initialize().then =>
#      data = {}
#      data[peggId] = prefId: prefId, userId: userId, tryCount: tryCount, timestamp: updatedAt
#      req =
#        method: "POST"
#        url: "#{FIREBASE_URL}/#{peggeeId}/pegg.json"
#        params:
#          auth: FIREBASE_SECRET
#        headers:
#          'X-HTTP-Method-Override': "PATCH"
#        body: JSON.stringify data
#        # data: JSON.stringify data
#        success: (res) => console.log "FIREBASE::savePegg: SUCCESS --- #{JSON.stringify res}"
#        error: (err) => console.error "FIREBASE::savePegg: ERROR! OMG. --- #{JSON.stringify err}"
#      Parse.Cloud.httpRequest req
#      console.log "FIREBASE::savePegg request --- #{JSON.stringify req}"
#
#  saveComment: (peggeeId, userId, prefId, commentId, updatedAt) =>
#    Firebase.initialize().then =>
#      data = {}
#      data[commentId] = prefId: prefId, userId: userId, commentId: commentId, timestamp: updatedAt
#      req =
#        method: "POST"
#        url: "#{FIREBASE_URL}/#{peggeeId}/comment.json"
#        params:
#          auth: FIREBASE_SECRET
#        headers:
#          'X-HTTP-Method-Override': "PATCH"
#        body: JSON.stringify data
#        # data: JSON.stringify data
#        success: (res) => console.log "FIREBASE::saveComment: SUCCESS --- #{JSON.stringify res}"
#        error: (err) => console.error "FIREBASE::saveComment: ERROR! OMG. --- #{JSON.stringify err}"
#      Parse.Cloud.httpRequest req
#      console.log "FIREBASE::saveComment request --- #{JSON.stringify req}"

module.exports = Firebase
