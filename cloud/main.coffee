_ = require 'underscore'
sha1 = require 'sha1'
facebookImporter = require './facebookImporter'
sendInBlue = require './sendInBlue'
Firebase = require '../lib/firebase'

######### CLOUD FUNCTIONS #########

Parse.Cloud.define "importFriends", (request, response) ->
  fbi = new facebookImporter
  fbi.start request.user
  .then =>
    message = "Updated #{request.user.get 'first_name'}'s friends from Facebook (Pegg user id #{request.user.id})"
    response.success message
  .fail (error) ->
    error.stack = new Error().stack
    response.error error

Parse.Cloud.define "getFirebaseToken", (request, response) ->
  response.success Firebase.getToken userId: request.user.id

Parse.Cloud.define "updateEmail", (request, response) ->
  email = request.params.newEmail
  firstName = request.params.firstName
  lastName = request.params.lastName
  sendInBlue.createOrUpdate {email, firstName, lastName}
  .then (res) =>
    sendInBlue.delete email: request.params.oldEmail
  .then (res) =>
    response.success "Updated email address successfully"
  .fail (err) =>
    response.error err

Parse.Cloud.define "toggleStar", (request, response) ->
  hasStarred = []
  author = ""
  quipId = request.params.quipId
  console.log "QUIPID:::   " + quipId
  user = request.user
  quipQuery = new Parse.Query 'Quip'
  quipQuery.equalTo 'objectId', quipId
  quipQuery.first({ useMasterKey: true })
  .then (quip) =>
    hasStarred = quip.get('hasStarred') or []
    author = quip.get('author')
    console.log "HAS STARRED:: " + hasStarred + " AUTHOR:: " + author.id
    if hasStarred.indexOf(user.id) > -1
      quip.remove 'hasStarred', user.id
      quip.increment 'starCount', -1
    else
      quip.addUnique 'hasStarred', user.id
      quip.increment 'starCount'
    quip.save(null, { useMasterKey: true })
  .then =>
    friendQuery = new Parse.Query 'User'
    friendQuery.equalTo 'objectId', author.id
    friendQuery.first({ useMasterKey: true })
  .then (friend) =>
    if hasStarred.indexOf(user.id) > -1
      friend.increment 'starCount', -1
    else
      friend.increment 'starCount'
    friend.save(null, { useMasterKey: true })
  .then =>
    response.success "toggleStar success"
    console.log "toggleStar success: #{quipId}"
  .fail (error) =>
    response.error error
    console.log 'toggleStar failed', error

Parse.Cloud.define "error", (request, response) ->
  if request.params?
    request.params.user ?=
      name: "Unknown user"
      id: "Unknown ID"
    request.params.error ?=
      stack: "Unknown error"
    body =
      channel: '#errors'
      username: 'PeggErrorBot'
      icon_emoji: ':ghost:'
      text: """
        *User*: #{request.params.user.name} (#{request.params.user.id})
        *UserAgent*: #{request.params.userAgent}
        ```#{request.params.error.message}```
        ```#{request.params.error.stack}```
      """
    # TODO Use slack.webhook instead. See uncaughtException() in index.coffee. Unify error handling code between these two places.
    Parse.Cloud.httpRequest
      method: "POST"
      headers:
        "Content-Type": "application/json"
      url: 'https://hooks.slack.com/services/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'
      body: body
    .catch (error) =>
      response.error error
    .then (res) =>
      response.success res

Parse.Cloud.define "feedback", (request, response) ->
  if request.params?
    friendId = request.params.id
    body =
      channel: '#feedback'
      username: request.params.name
      icon_emoji: ':unicorn_face:'
      text: """
        *UserId*: #{friendId}
        *Email*: #{request.params.email}
        *UserAgent*: #{request.params.userAgent}
        *Context*: #{request.params.context}
        ```#{request.params.feedback}```
      """
    Parse.Cloud.httpRequest
      method: "POST"
      headers:
        "Content-Type": "application/json"
      url: 'https://hooks.slack.com/services/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'
      body: body
    .catch (error) =>
      response.error error
    .then (res) =>
      response.success res

    # add cosmic unicorn to user's friend role
    roleQuery = new Parse.Query Parse.Role
    roleQuery.equalTo 'name', "#{friendId}_Friends"
    getUserPromise = roleQuery.first({ useMasterKey: true })
    cosmicQuery = new Parse.Query Parse.User
    cosmicQuery.equalTo 'objectId', 'A2UBfjj8n9'
    getCosmicPromise = cosmicQuery.first({ useMasterKey: true })
    Parse.Promise.when(getUserPromise, getCosmicPromise)
    .then (userRole, cosmicUser) =>
      if userRole? and cosmicUser?
        relation = userRole.getUsers()
        relation.add cosmicUser
        userRole.save(null, { useMasterKey: true })
    .fail (error) =>
      console.error "56", error

Parse.Cloud.define "requestFriend", (request, response) ->
  user = request.user
  friend = new Parse.User
  friend.id = request.params.friendId
  friendPublics = new Parse.Object 'UserPublics'
  friendPublics.id = request.params.friendPublicsId
  userPublics = new Parse.Object 'UserPublics'
  userPublics.id = request.params.userPublicsId
  saveFriendRequest user, friend, friendPublics, userPublics
  .then (res) =>
    response.success res

Parse.Cloud.define "confirmRequest", (request, response) ->
  user = request.user
  friend = new Parse.User
  friend.id = request.params.friendId
  console.log friend, user
  deleteFriendRequest friend, user # reverse order because we're deleting the request the other user made
  .then (res) =>
    console.log res
    if res?
      createFriendship user.id, friend.id
      response.success res
    else
      response.error res

Parse.Cloud.define "addFriend", (request, response) ->
  userId = request.user.id
  friendId = request.params.friendId
  createFriendship userId, friendId

######### AFTER SAVE, DELETE, ETC #########

Parse.Cloud.afterSave '_User', (request) ->
  user = request.object
  user.fetch({ useMasterKey: true })
  .then (user) =>
    if !user.existed()
      facebookId = user.get 'facebook_id'
      if !facebookId?
      # Create friend role for a email/pass login (non FB)
        roleName = "#{user.id}_Friends"
        console.log "creating role", roleName
        roleAcl = new Parse.ACL()
        role = new Parse.Role roleName, roleAcl
        role.save(null, { useMasterKey: true })

#Parse.Cloud.afterSave 'Zing', (request) ->
#  user = request.user
#  friend = request.object.get 'friend'
#  token = user.getSessionToken()
#  bestieQuery = new Parse.Query 'Bestie'
#  bestieQuery.equalTo 'friend', friend
#  bestieQuery.equalTo 'user', user
#  bestieQuery.first({ sessionToken: token })
#  .then (bestie) ->
#    bestie.set 'lastZingDate', Date.now()
#    bestie.save(null, { useMasterKey: true })
#    .then => console.log "updateBestieZing: success -- #{JSON.stringify bestie}"
#    .fail (err) => console.error "updateBestieZing: ERROR -- #{JSON.stringify bestie}", err

Parse.Cloud.afterSave 'Pegg', (request) ->
  user = request.user
  if !request.object.existed()
    pref = request.object.get 'pref'
    card = request.object.get 'card'
    peggee = request.object.get 'peggee'
    guess = request.object.get 'guess'
    answer = request.object.get 'answer'
    question = request.object.get 'question'
    failCount = request.object.get 'failCount'
    deck = request.object.get 'deck'

    # Correct! Save stats and update Bestie Score
    if guess.id is answer.id
      updatePrefStats { user, card, pref, guess, failCount, correctAnswer: true }
      updateBestieScore user, peggee, failCount, deck
    else
      updatePrefStats { user, card, pref, guess, failCount, correctAnswer: false }

Parse.Cloud.afterSave 'Pref', (request) ->
  pref = request.object
  user = request.user
  card = request.object.get 'card'
  answer = request.object.get 'answer'
  deck = request.object.get 'deck'
  question = request.object.get 'question'
  if !pref.existed() # if new object
    updateCardHasPreffed user, card # updates hasPreffed on Card
    incrementChoiceCount answer.id, 'prefCount' # what's the most popular preference?

Parse.Cloud.afterSave 'UserPrivates', (request) ->
# can't use afterSave Parse.User because on new user creation two saves happen, the first without any user details
  userPrivates = request.object
  if !userPrivates.existed() # if new object
    email = userPrivates.get 'email'
    firstName = userPrivates.get 'firstName'
    lastName = userPrivates.get 'lastName'
    console.log "subscribing to SendInBlue:", JSON.stringify {email, firstName, lastName}
    sendInBlue.createOrUpdate {email, firstName, lastName}
    .then (res) =>
      console.log res




######### UPDATES #########
updatePrefStats = ({ user, card, pref, guess, failCount, correctAnswer }) ->
  console.error "updatePrefStats:", pref
  token = user.getSessionToken()
  pref.fetch({sessionToken: token})
    .fail (err) => console.error "updatePrefStats: ERROR -- #{JSON.stringify err}"
    .then (pref) =>
      console.log "updatePrefStats: fetched pref -- #{JSON.stringify pref}"
      choices = pref.get('choices')
      firstTry = failCount is 0
      if correctAnswer
        # UPDATE Pref with userId in hasPegged array
        pref.addUnique 'hasPegged', user.id
      if firstTry
        if choices?
          choices[guess.id].peggCount++
          pref.set 'choices', choices
        else
          # Sometimes choices don't get populated on Pref creation, not sure why
          console.log "ERROR: aaaaarg choices should exist... refetching..."
          getChoices(card)
            .then (choices) =>
              choices[guess.id].peggCount++
              pref.set 'choices', choices
              pref.save(null, { useMasterKey: true })
      if correctAnswer or firstTry
        pref.save(null, { useMasterKey: true })
          .fail (err) => console.error "updatePrefStats: ERROR -- #{JSON.stringify err}"
          .then => console.log "updatePrefStats: success -- #{JSON.stringify pref}"

createFriendship = (userId, friendId) ->
  Parse.Promise.when(
    addFriendToRole("#{friendId}_Friends", userId)
    addFriendToRole("#{userId}_Friends", friendId)
  ).then =>
    Firebase.fanOut
      userId: userId
      friendIds: [friendId]
      timestamp: Date.now()

getFriendRequest = (user, friend) ->
  requestQuery = new Parse.Query 'Request'
  requestQuery.equalTo 'friend', friend
  requestQuery.equalTo 'user', user
  requestQuery.first({ useMasterKey: true })

deleteFriendRequest = (user, friend) ->
  getFriendRequest user, friend
  .then (res) =>
    console.log "getFriend Result: ", res
    if res? then res.destroy({ useMasterKey: true })

saveFriendRequest = (user, friend, friendPublics, userPublics) ->
  getFriendRequest user, friend
  .then (res) ->
    unless res?
      newRequestACL = new Parse.ACL()
      newRequestACL.setReadAccess friend.id, true
      newRequestACL.setReadAccess user.id, true
      newRequest = new Parse.Object 'Request'
      newRequest.set 'user', user
      newRequest.set 'friend', friend
      newRequest.set 'friendPublics', friendPublics
      newRequest.set 'userPublics', userPublics
      newRequest.set 'ACL', newRequestACL
      newRequest.save(null, { useMasterKey: true })

updateBestieScore = (user, peggee, failCount, deck) ->
  token = user.getSessionToken()
  bestieQuery = new Parse.Query 'Bestie'
  bestieQuery.equalTo 'friend', peggee
  bestieQuery.equalTo 'user', user
  bestieQuery.first({ sessionToken: token })
    .then (bestie) ->
      if bestie?
        peggCounts = bestie.get('peggCounts') or {}
        if peggCounts[deck]? then peggCounts[deck]++ else peggCounts[deck] = 1
        bestie.set 'peggCounts', peggCounts
        bestie.set 'lastDeck', deck
        bestie.increment 'failCount', failCount
        bestie.increment 'peggCount'
        score = Math.round(( 1 - bestie.get('failCount') / (bestie.get('peggCount') + bestie.get('failCount'))) * 100)
        bestie.set 'score', score
        bestie.save(null, { useMasterKey: true })
          .then => console.log "updateBestieScore: success -- #{JSON.stringify bestie}"
          .fail (err) => console.error "updateBestieScore: ERROR -- #{JSON.stringify bestie}", err
      else
        newBestieAcl = new Parse.ACL()
        newBestieAcl.setRoleReadAccess "#{user.id}_Friends", true
        newBestieAcl.setRoleReadAccess "#{peggee.id}_Friends", true
        newBestieAcl.setReadAccess user.id, true
        newBestie = new Parse.Object 'Bestie'
        newBestie.set 'failCount', failCount
        newBestie.set 'peggCount', 1
        newBestie.set 'friend', peggee
        newBestie.set 'user', user
        newBestie.set 'lastDeck', deck
        peggCounts = {}
        if peggCounts[deck]? then peggCounts[deck]++ else peggCounts[deck] = 1
        newBestie.set 'peggCounts', peggCounts
        score = Math.round(( 1 - newBestie.get('failCount') / (newBestie.get('peggCount') + newBestie.get('failCount'))) * 100)
        newBestie.set 'score', score
        newBestie.set 'ACL', newBestieAcl
        newBestie.save(null, { useMasterKey: true })
          .then => console.log "updateBestieScore: success"
          .fail (err) => console.error "updateBestieScore: ERROR -- #{JSON.stringify newBestie}", err

updateCardHasPreffed = (user, card) ->
  token = user.getSessionToken()
  card.fetch({sessionToken: token})
    .then (card) =>
      if card.get('hasPreffed') is undefined
        card.set 'hasPreffed', []
      card.addUnique 'hasPreffed', user.id
      card.save(null, { useMasterKey: true })
        .fail (error) ->
          console.log 'hasPreffed failed', error
        .then =>
          console.log "hasPreffed saved: #{card.id}"

addFriendToRole = (roleName, friendId) ->
  promise = new Parse.Promise()
  query = new Parse.Query Parse.Role
  query.equalTo "name", roleName
  query.first({ useMasterKey: true })
  .then (role) =>
    if role?
      relation = role.getUsers()
      query = new Parse.Query Parse.User
      query.equalTo "objectId", friendId
      query.first({ useMasterKey: true })
      .then (friend) =>
        relation.add friend
        role.save(null, { useMasterKey: true })
      .then =>
        promise.resolve()
      .fail (error) =>
        console.error "75", error
        promise.reject error
    else
      promise.reject "role missing: #{roleName}"
  .fail (error) =>
    console.error "79", error
    promise.reject error
  promise

######### HELPERS #########

# returns {<id>: {text: 'hey', peggCount: 0}, <id2>: ...}
# requires useMasterKey
getChoices = (card) ->
  choiceQuery = new Parse.Query 'Card'
  choiceQuery.equalTo 'objectId', card.id
  choiceQuery.first({ useMasterKey: true })
    .then (result) =>
      if result?
        choices = result.get('choices')
        for own id, choice of choices
          choice.peggCount = 0
        return choices
      else
        return null

incrementChoiceCount = (choiceId, fieldName) ->
  choiceQuery = new Parse.Query 'Choice'
  choiceQuery.equalTo 'objectId', choiceId
  choiceQuery.first({ useMasterKey: true })
    .then (result) =>
      if result?
        result.increment fieldName, 1
        result.save(null, { useMasterKey: true })
