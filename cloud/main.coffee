_ = require 'underscore'
sha1 = require 'sha1'
sendInBlue = require '../lib/sendInBlue'
slack = require '../lib/slack'
Firebase = require '../lib/firebase'

###################################
######### CLOUD FUNCTIONS #########

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

Parse.Cloud.define "error", (request, response) ->
  if request.params?
    user = request.params.user or { name: "Unknown user", id: "Unknown ID" }
    error = request.params.error or { stack: "Unknown error" }
    userAgent = request.params.userAgent or ''
    slack.clientError error, user, userAgent
    .then (res) =>
      response.success res
    .fail (err) =>
      response.error err

Parse.Cloud.define "feedback", (request, response) ->
  if request.params?
    user =
      id: request.params.id
      email: request.params.email
      name: request.params.name
    userAgent = request.params.userAgent or ''
    context = request.params.context or ''
    feedback = request.params.feedback or ''
    slack.userFeedback user, userAgent, context, feedback
    .then (res) =>
      response.success res
    .fail (err) =>
      response.error err
    # add cosmic unicorn to user's friend role
    addFriendToRole("#{user.id}_Friends", 'A2UBfjj8n9')

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
  # delete the request the other user made
  deleteFriendRequest friend, user
  .then (res) =>
    if res?
      createFriendship user.id, friend.id
      response.success res
    else
      response.error res

Parse.Cloud.define "addFriend", (request, response) ->
  userId = request.user.id
  friendId = request.params.friendId
  createFriendship userId, friendId

Parse.Cloud.define "createCard", (request, response) ->
  # console.log 'CARD: ', JSON.stringify request.params.card
  createCard request.user, request.params.card
  .then (res) =>
    response.success res
  .fail (error) =>
    response.error error

###########################################
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
  author = request.object.get 'author'
  answer = request.object.get 'answer'
  deck = request.object.get 'deck'
  question = request.object.get 'question'
  if !pref.existed() # if new object
    updateCardHasPreffed user, card # updates hasPreffed on Card
    incrementChoiceCount answer.id, 'prefCount' # what's the most popular preference?
    if author.id?
      incrementStars author.id

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

###########################
######### HELPERS #########

# TODO: set class level ACL on Card to Public Read only
createCard = (user, card) ->
  cardPromise = new Parse.Promise
  newCardAcl = new Parse.ACL user
  newCardAcl.setRoleReadAccess "#{user.id}_Friends", true
  newCard = new Parse.Object 'Card'
  newCard.set 'question', card.question
  newCard.set 'createdBy', user
  newCard.set 'disabled', true
  newCard.set 'publishDate', new Date
  newCard.set 'deck', 'Friends'
  newCard.set 'ACL', newCardAcl
  newCard.save(null, { useMasterKey: true })
  .then (newCard) =>
    saved = for choice in card.choices
      saveChoice user.id, newCard.id, choice
    Parse.Promise.when saved
    .then (choices...) =>
      cardChoices = _.indexBy choices[0], 'id'
      finishCardCreation newCard, cardChoices

saveChoice = (userId, cardId, answer) ->
  choicePromise = new Parse.Promise
  createdBy = new Parse.User
  createdBy.set 'id', userId
  card = new Parse.Object 'Card'
  card.set 'id', cardId
  acl = new Parse.ACL createdBy
  acl.setPublicReadAccess false
  choice = new Parse.Object 'Choice'
  choice.set 'text', answer.text
  choice.set 'image', answer.image
  choice.set 'card', card
  choice.set 'createdBy', createdBy
  choice.set 'ACL', acl
  choice.save(null, { useMasterKey: true })
  .then (choice) =>
    choicePromise.resolve
      id: choice.id
      cardId: choice.get('card')?.id
      text: choice.get('text')
      image: choice.get('image')
  .fail (error) =>
    console.log "ERROR:   ", error
    choicePromise.reject error
  choicePromise

finishCardCreation = (card, choices) ->
  card.set 'choices', choices
  card.set 'disabled', false
  card.save(null, { useMasterKey: true })

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
        # TODO: Sometimes choices don't get populated on Pref creation, not sure why
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

incrementStars = (authorId) ->
  userQuery = new Parse.Query 'User'
  userQuery.equalTo 'objectId', authorId
  userQuery.first({ useMasterKey: true })
  .then (user) =>
    user.increment 'starCount'
    user.save(null, { useMasterKey: true })
  .then =>
    console.log "incrementStars success: #{authorId}"
  .fail (error) =>
    console.error 'incrementStars fail', error


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
